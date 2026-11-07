#!/usr/bin/env python3
"""Read-only stage validation. Never builds/signs/installs/notarizes/publishes."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MODES = ('developer', 'hardware-test', 'release-candidate', 'production')
HARDWARE_TESTS = ('enumeration', 'slot-mapping', 'internal-clock', 'external-clock',
                  'port2-dma', '64-channel-audio', 'rate-changes', 'reconnect', 'stability')

def digest(path):
    path = Path(path)
    h = hashlib.sha256()
    if path.is_file():
        with path.open('rb') as source:
            for block in iter(lambda: source.read(1024 * 1024), b''): h.update(block)
    else:
        for item in sorted(path.rglob('*')):
            relative = item.relative_to(path).as_posix().encode()
            if item.is_symlink():
                h.update(b'L' + relative + b'\0' + str(item.readlink()).encode())
            elif item.is_file():
                h.update(b'F' + relative + b'\0' + digest(item).encode())
    return h.hexdigest()

def external_file(value):
    path = Path(value).expanduser().resolve()
    if path.is_relative_to(ROOT) or not path.is_file():
        raise ValueError('missing external profile; profiles must remain outside repository')
    return path

def validate_profile(profile, team, identifier, role, certificate, passive_identifier):
    errors = []
    ent = profile.get('Entitlements', {})
    if profile.get('TeamIdentifier') != [team]: errors.append(f'{role}: profile team mismatch')
    appid = ent.get('com.apple.application-identifier', ent.get('application-identifier'))
    if appid != f'{team}.{identifier}': errors.append(f'{role}: profile identifier mismatch')
    expiration = profile.get('ExpirationDate')
    if not isinstance(expiration, datetime) or expiration.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        errors.append(f'{role}: profile expired or missing expiry')
    hashes = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates', [])}
    if certificate.upper() not in hashes: errors.append(f'{role}: supplied certificate not in profile')
    if role in ('driver', 'passiveDriver'):
        if ent.get('com.apple.developer.driverkit') is not True: errors.append(f'{role}: DriverKit not approved')
        if not ent.get('com.apple.developer.driverkit.transport.pci'): errors.append(f'{role}: PCI transport not approved')
    if role == 'driver' and ent.get('com.apple.developer.driverkit.family.audio') is not True:
        errors.append('driver: AudioDriverKit not approved')
    if role == 'app' and ent.get('com.apple.developer.system-extension.install') is not True:
        errors.append('app: extension installation permission missing')
    if role == 'diagnostic' and passive_identifier not in ent.get('com.apple.developer.driverkit.userclient-access', []):
        errors.append('diagnostic: own passive driver user-client access missing')
    return errors

def evaluate(config, mode, inspect=False, current_source=None):
    if mode not in MODES: return ['unknown build class']
    if mode == 'developer': return []
    errors = []
    if not isinstance(config, dict): return ['manifest must be an object']
    for field in ('identifiers', 'profiles', 'artifacts', 'hardwareEvidence', 'installer'):
        if field in config and not isinstance(config[field], dict): return [f'{field} must be an object']
    if current_source is None or config.get('sourceCommit') != current_source:
        errors.append('manifest must match the inspected source checkout commit')
    if config.get('schemaVersion') != 1: errors.append('external manifest schemaVersion must be 1')
    team = config.get('teamID', '')
    if not re.fullmatch(r'[A-Z0-9]{10}', team) or team == '95CX6P84C4':
        errors.append('own approved Apple team required; upstream team forbidden')
    ids = config.get('identifiers', {})
    roles = ('app', 'diagnostic', 'passiveDriver') if mode == 'hardware-test' else ('app', 'diagnostic', 'passiveDriver', 'driver')
    values = [ids.get(role, '') for role in roles]
    if len(set(values)) != len(values) or any(not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', x)
        or x.startswith('com.danielraffel.') or 'REPLACE' in x or 'YOUR' in x for x in values):
        errors.append('distinct own registered app/driver/diagnostic identifiers required')
    certificate = config.get('applicationCertificateSHA1', '')
    if not re.fullmatch(r'[A-Fa-f0-9]{40}', certificate): errors.append('explicit own application certificate SHA-1 required')
    if not inspect: errors.append('signed artifacts/profiles have not been inspected on macOS')
    for role in roles:
        try:
            path = external_file(config.get('profiles', {}).get(role, ''))
            if inspect:
                raw = subprocess.run(['security', 'cms', '-D', '-i', str(path)], check=True, capture_output=True).stdout
                errors += validate_profile(plistlib.loads(raw), team, ids.get(role, ''), role, certificate, ids.get('passiveDriver'))
        except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException):
            errors.append(f'{role}: approved external profile unavailable or invalid')
        artifact = config.get('artifacts', {}).get(role, {})
        if not isinstance(artifact, dict):
            errors.append(f'{role}: artifact record must be an object'); continue
        path = Path(artifact.get('path', ''))
        if not path.exists() or not artifact.get('sha256') or digest(path) != artifact.get('sha256'):
            errors.append(f'{role}: signed artifact/hash missing or mismatched')
        elif inspect:
            try:
                subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True, capture_output=True)
                info = subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], check=True, capture_output=True).stderr.decode()
                if f'TeamIdentifier={team}\n' not in info or f'Identifier={ids.get(role)}\n' not in info:
                    errors.append(f'{role}: loaded signature team/identifier mismatch')
            except (OSError, subprocess.CalledProcessError): errors.append(f'{role}: signature verification failed')
    if mode in ('release-candidate', 'production'):
        evidence = config.get('hardwareEvidence', {})
        if not re.fullmatch(r'[a-f0-9]{40}', evidence.get('sourceCommit', '')):
            errors.append('exact hardware-tested source commit missing')
        tests = evidence.get('tests', {})
        if not isinstance(tests, dict): tests = {}
        for name in HARDWARE_TESTS:
            record = tests.get(name, {})
            if not isinstance(record, dict): record = {}
            if record.get('result') != 'passed' or not record.get('reportReference'):
                errors.append(f'hardware acceptance missing: {name}')
        if evidence.get('sourceCommit') != config.get('sourceCommit'):
            errors.append('hardware-tested source does not match candidate source')
        hashes = evidence.get('testedArtifactHashes', {})
        if not isinstance(hashes, dict) or not hashes:
            errors.append('hardware-tested binary hashes missing')
        else:
            for role in roles:
                if hashes.get(role) != config.get('artifacts', {}).get(role, {}).get('sha256') or not hashes.get(role):
                    errors.append(f'{role}: hardware-tested artifact differs from candidate')
        if not config.get('approvalReference'): errors.append('explicit release approval reference missing')
        installer = config.get('installer', {})
        path = Path(installer.get('path', ''))
        if not path.is_file() or not installer.get('sha256') or digest(path) != installer.get('sha256'):
            errors.append('exact signed installer/hash unavailable')
        elif inspect:
            try:
                signed = subprocess.run(['pkgutil', '--check-signature', str(path)], check=True, capture_output=True).stdout.decode()
                if team not in signed: errors.append('installer signer team mismatch')
                if mode == 'production':
                    subprocess.run(['xcrun', 'stapler', 'validate', str(path)], check=True, capture_output=True)
            except (OSError, subprocess.CalledProcessError): errors.append('installer signature/notarization validation failed')
    return errors

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=MODES, default='developer')
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--inspect-signed', action='store_true', help='read profiles/signatures with macOS tools; no mutation')
    args = parser.parse_args()
    try:
        config = json.loads(args.manifest.read_text()) if args.manifest else {}
        source = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], check=True, capture_output=True, text=True).stdout.strip()
        errors = evaluate(config, args.mode, inspect=args.inspect_signed, current_source=source)
        if args.mode != 'developer':
            for flags in (['diff', '--quiet'], ['diff', '--cached', '--quiet']):
                if subprocess.run(['git', '-C', str(ROOT)] + flags, capture_output=True).returncode:
                    errors.append('source checkout has uncommitted changes')
    except (ValueError, OSError, TypeError) as error:
        errors = [f'invalid manifest: {type(error).__name__}']
    report = {'mode': args.mode, 'status': 'blocked' if errors else 'checks-passed',
              'blockers': errors, 'hardwareAcceptanceEstablishedByThisTool': False,
              'publishesOrInstalls': False, 'unsignedDeveloperArtifactsAreHardwareProof': False}
    print(json.dumps(report, indent=2))
    return 2 if errors else 0
if __name__ == '__main__': sys.exit(main())
