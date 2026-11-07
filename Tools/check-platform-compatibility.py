#!/usr/bin/env python3
"""Check Sequoia/Tahoe deployment metadata, Mach-O floors and optional GUI startup.
No signing, activation, audio I/O, vendor requests or production app launch.
"""
import argparse
import json
from pathlib import Path
import platform
import plistlib
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def version(value):
    parts = tuple(int(part) for part in str(value).split('.'))
    return (parts + (0, 0, 0))[:3]

def source_errors(root, policy):
    errors = []
    if policy.get('schemaVersion') != 1 or policy.get('architecture') != 'arm64':
        errors.append('unsupported platform policy')
    app = plistlib.loads((root / 'Apps/Maestro/MaestroApp/Resources/Info.plist').read_bytes())
    if version(app['LSMinimumSystemVersion']) != version(policy['minimumMacOS']):
        errors.append('shipping app minimum differs from policy')
    for name in ('Drivers/Thunderbolt/Info.plist', 'Drivers/Thunderbolt/Diagnostics/Info.plist.in'):
        info = plistlib.loads((root / name).read_bytes())
        if version(info['OSMinimumDriverKitVersion']) != version(policy['minimumDriverKit']):
            errors.append(f'{name}: DriverKit minimum differs from policy')
    installer = ET.parse(root / 'Installer/distribution.xml')
    floors = installer.findall('./allowed-os-versions/os-version')
    if len(floors) != 1: errors.append('installer must have one explicit OS minimum')
    for floor in floors:
        if version(floor.attrib['min']) != version(policy['minimumMacOS']):
            errors.append('installer minimum differs from policy')
    package = (root / 'Apps/Maestro/Package.swift').read_text()
    if f'.macOS(.v{version(policy["minimumMacOS"])[0]})' not in package:
        errors.append('Swift package deployment differs from policy')
    for name in ('build.sh', 'build-passive-diagnostics.sh'):
        script = (root / 'Drivers/Thunderbolt/Scripts' / name).read_text()
        if 'Tools/lib/platform-targets.sh' not in script or '--deployment-target "$MAESTRO_DRIVERKIT_DEPLOYMENT_TARGET"' not in script:
            errors.append(f'{name}: shared DriverKit target not used')
        if '-Werror=unguarded-availability' not in script or re.search(r'apple-driverkit\d', script):
            errors.append(f'{name}: unguarded availability or hard-coded target')
    return errors

def inspect_macho(path):
    data = Path(path).read_bytes()
    if len(data) < 32: raise ValueError('truncated Mach-O header')
    header = struct.unpack_from('<8I', data)
    if header[0] != 0xFEEDFACF or header[1] != 0x0100000C or header[2] & 0xFFFFFF != 0:
        raise ValueError('expected thin arm64 Mach-O executable')
    commands, size = header[4:6]
    if size > len(data) - 32 or commands > size // 8: raise ValueError('truncated Mach-O commands')
    offset, builds = 32, []
    for _ in range(commands):
        if offset + 8 > 32 + size: raise ValueError('truncated load command')
        command, count = struct.unpack_from('<2I', data, offset)
        if count < 8 or offset + count > 32 + size: raise ValueError('invalid load command size')
        if command == 0x32:
            if count < 24: raise ValueError('short LC_BUILD_VERSION')
            target, minimum, sdk, _ = struct.unpack_from('<4I', data, offset + 8)
            decode = lambda raw: (raw >> 16, (raw >> 8) & 255, raw & 255)
            builds.append((target, decode(minimum), decode(sdk)))
        offset += count
    if len(builds) != 1: raise ValueError('missing/ambiguous LC_BUILD_VERSION')
    return builds[0]

def binary_errors(paths, policy):
    errors, records = [], []
    for path in paths:
        try:
            target, floor, sdk = inspect_macho(path)
            expected = policy['minimumMacOS'] if target == 1 else policy['minimumDriverKit'] if target == 10 else None
            if expected is None or floor != version(expected):
                errors.append(f'{path}: unexpected platform/deployment {target}/{floor}')
            records.append({'file': str(path), 'platform': target, 'minimum': floor, 'sdk': sdk, 'architecture': 'arm64'})
        except (ValueError, OSError, struct.error) as error:
            errors.append(f'{path}: {error}')
    return errors, records

def preview_errors(bundle, policy):
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    errors = []
    if info.get('CFBundleIdentifier') != 'com.kiwimartin.symphonymaestro.preview': errors.append('unexpected preview identity')
    if version(info.get('LSMinimumSystemVersion', '0')) != version(policy['minimumMacOS']): errors.append('preview deployment differs from policy')
    if 'SUFeedURL' in info or (bundle / 'Contents/Library/SystemExtensions').exists(): errors.append('preview must not contain updater/extension activation inputs')
    if info.get('CFBundleExecutable') != 'LegacyMaestroPreview': errors.append('unexpected preview executable')
    return errors

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner-label')
    parser.add_argument('--preview-bundle', type=Path)
    parser.add_argument('--binaries', nargs='+', type=Path, default=[])
    parser.add_argument('--smoke-preview', action='store_true')
    args = parser.parse_args()
    policy = json.loads((ROOT / 'Tools/platform-compatibility.json').read_text())
    errors = source_errors(ROOT, policy)
    host = None
    if args.runner_label:
        host = subprocess.check_output(['sw_vers', '-productVersion'], text=True).strip()
        if policy['testedRunnerMajors'].get(args.runner_label) != version(host)[0]: errors.append('runner does not execute the requested macOS release')
        if platform.machine() != policy['architecture']: errors.append('runner must execute tests natively on Apple Silicon')
    failures, records = binary_errors(args.binaries, policy); errors += failures
    if args.preview_bundle:
        errors += preview_errors(args.preview_bundle, policy)
    preview_started = False
    if args.smoke_preview:
        if not args.preview_bundle or errors:
            errors.append('valid assembled preview required before smoke launch')
        else:
            try:
                result = subprocess.run([str(args.preview_bundle.resolve() / 'Contents/MacOS/LegacyMaestroPreview'), '--smoke-test'],
                                        text=True, capture_output=True, timeout=30)
                if result.returncode or 'LEGACY_PREVIEW_SMOKE_OK' not in result.stdout:
                    errors.append(f'preview did not create a visible window (exit {result.returncode}): {result.stderr[-2000:]}')
                else: preview_started = True
            except (OSError, subprocess.TimeoutExpired): errors.append('preview startup failed or exceeded 30 seconds')
    print(json.dumps({'policy': policy, 'hostMacOS': host, 'binaries': records,
                      'previewWindowSmokeRequested': args.smoke_preview, 'previewVisibleWindowStarted': preview_started,
                      'errors': errors, 'hardwareValidated': False}, indent=2))
    return 1 if errors else 0
if __name__ == '__main__': sys.exit(main())
