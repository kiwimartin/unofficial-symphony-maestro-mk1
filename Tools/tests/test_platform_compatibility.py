import importlib.util
import json
from pathlib import Path
import shutil
import struct
import tempfile
import os
import subprocess
import unittest
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('compatibility', ROOT / 'Tools/check-platform-compatibility.py')
compat = importlib.util.module_from_spec(spec); spec.loader.exec_module(compat)
POLICY = json.loads((ROOT / 'Tools/platform-compatibility.json').read_text())
class PlatformCompatibility(unittest.TestCase):
    def test_source_versions_agree_for_all_components(self):
        self.assertEqual(compat.source_errors(ROOT, POLICY), [])
    def test_changed_installer_floor_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('Apps/Maestro/MaestroApp/Resources/Info.plist', 'Drivers/Thunderbolt/Info.plist',
                'Drivers/Thunderbolt/Diagnostics/Info.plist.in', 'Installer/distribution.xml', 'Apps/Maestro/Package.swift',
                'Drivers/Thunderbolt/Scripts/build.sh', 'Drivers/Thunderbolt/Scripts/build-passive-diagnostics.sh'):
                (root / name).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ROOT / name, root / name)
            installer = root / 'Installer/distribution.xml'
            installer.write_text(installer.read_text().replace('min="15.0"', 'min="26.0"'))
            self.assertIn('installer minimum differs from policy', compat.source_errors(root, POLICY))
    def macho(self, target, floor, cpu=0x0100000C):
        return struct.pack('<8I', 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0) + struct.pack('<6I', 0x32, 24, target, floor << 16, 26 << 16, 0)
    def test_actual_binary_floor_and_architecture_must_match(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'binary'
            for target, floor in ((1, 15), (10, 24)):
                path.write_bytes(self.macho(target, floor)); errors, records = compat.binary_errors([path], POLICY)
                self.assertEqual(errors, []); self.assertEqual(records[0]['architecture'], 'arm64')
            path.write_bytes(self.macho(1, 26)); self.assertTrue(compat.binary_errors([path], POLICY)[0])
            path.write_bytes(self.macho(1, 15, cpu=0x01000007)); self.assertTrue(compat.binary_errors([path], POLICY)[0])
    def test_truncated_or_malformed_macho_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'binary'
            for data in (b'bad', self.macho(1, 15)[:-1], self.macho(1, 15)[:32], b'\0' * 64):
                path.write_bytes(data); self.assertTrue(compat.binary_errors([path], POLICY)[0])
    def test_conflicting_driver_deployment_override_is_rejected_before_sdk_access(self):
        env = dict(os.environ, MAESTRO_DRIVERKIT_DEPLOYMENT_TARGET='25.2')
        result = subprocess.run(['bash', '-c', '. "$1"', 'test', str(ROOT / 'Tools/lib/platform-targets.sh')],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('conflicts with shared deployment policy', result.stderr)
    def test_version_comparison_treats_missing_patch_as_zero(self):
        self.assertEqual(compat.version('15.0'), compat.version('15.0.0'))
if __name__ == '__main__': unittest.main()
