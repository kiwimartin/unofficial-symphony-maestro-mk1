#!/usr/bin/env python3
"""Assemble an unsigned, isolated configuration GUI; no signing or installation."""
import argparse
from pathlib import Path
import plistlib
import json
import shutil

def assemble(binary, output):
    binary, output = Path(binary), Path(output)
    if not binary.is_file() or output.exists() or output.suffix != '.app':
        raise ValueError('existing input executable and a new .app output path required')
    executable = output / 'Contents/MacOS/LegacyMaestroPreview'
    executable.parent.mkdir(parents=True)
    shutil.copy2(binary, executable)
    executable.chmod(executable.stat().st_mode | 0o111)
    root = Path(__file__).resolve().parents[1]
    policy = json.loads((root / 'Tools/platform-compatibility.json').read_text())
    info = {'CFBundleIdentifier': 'com.kiwimartin.symphonymaestro.preview',
            'CFBundleExecutable': 'LegacyMaestroPreview', 'CFBundleName': 'Legacy Symphony Preview',
            'CFBundleDisplayName': 'Legacy Symphony Developer Preview', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.1.0',
            'LSMinimumSystemVersion': policy['minimumMacOS'], 'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication'}
    (output / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    resources = output / 'Contents/Resources'; resources.mkdir()
    (resources / 'DEVELOPER-ONLY.txt').write_text(
        'Unsigned developer configuration/diagnostic GUI. Not a release or installer.\n'
        'No Sparkle feed, system extension, activation, vendor write or audio engine.\n'
        'Hardware controls are unavailable until approved signing and hardware validation.\n')
    shutil.copy2(root / 'license.md', resources / 'LICENSE.md')
    shutil.copy2(root / 'Apps/Maestro/MaestroApp/Resources/Acknowledgements.html', resources / 'Acknowledgements.html')
    return output
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path); parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(assemble(args.binary, args.output))
