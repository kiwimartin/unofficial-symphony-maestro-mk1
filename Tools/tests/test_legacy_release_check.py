import hashlib
import importlib.util
from pathlib import Path
from datetime import datetime, timedelta, timezone
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('release_check', Path(__file__).resolve().parents[1] / 'legacy-release-check.py')
release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
class ReleaseGates(unittest.TestCase):
    def test_developer_cannot_establish_hardware_release(self):
        self.assertEqual(release.evaluate({}, 'developer'), [])
        for mode in ('hardware-test', 'release-candidate', 'production'):
            self.assertTrue(release.evaluate({}, mode))
    def test_upstream_team_and_identifiers_rejected(self):
        errors = release.evaluate({'schemaVersion': 1, 'teamID': '95CX6P84C4',
            'identifiers': {'app': 'com.danielraffel.maestro'}}, 'hardware-test')
        self.assertTrue(any('upstream' in e for e in errors))
        self.assertTrue(any('distinct own' in e for e in errors))
    def test_profile_matches_exact_team_id_certificate_and_permission(self):
        cert = b'public-test-certificate-data'
        sha = hashlib.sha1(cert).hexdigest()
        profile = {'TeamIdentifier': ['ABCDE12345'], 'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=1),
            'DeveloperCertificates': [cert], 'Entitlements': {'application-identifier': 'ABCDE12345.test.own.passive',
            'com.apple.developer.driverkit': True, 'com.apple.developer.driverkit.transport.pci': [{'IOPCIPrimaryMatch': '0x220019c2'}]}}
        self.assertEqual(release.validate_profile(profile, 'ABCDE12345', 'test.own.passive', 'passiveDriver', sha, 'test.own.passive'), [])
        self.assertTrue(release.validate_profile(profile, 'OTHER12345', 'test.own.passive', 'passiveDriver', sha, 'test.own.passive'))
        self.assertTrue(release.validate_profile(profile, 'ABCDE12345', 'test.wrong', 'passiveDriver', sha, 'test.own.passive'))
        self.assertTrue(release.validate_profile(profile, 'ABCDE12345', 'test.own.passive', 'driver', sha, 'test.own.passive'))
        profile['ExpirationDate'] = datetime.now(timezone.utc) - timedelta(seconds=1)
        self.assertTrue(release.validate_profile(profile, 'ABCDE12345', 'test.own.passive', 'passiveDriver', sha, 'test.own.passive'))
    def test_digest_detects_changes_and_does_not_follow_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'binary').write_bytes(b'1')
            first = release.digest(root); (root / 'binary').write_bytes(b'2')
            self.assertNotEqual(first, release.digest(root))
            (root / 'external').symlink_to('/nonexistent-no-secret-read')
            self.assertEqual(len(release.digest(root)), 64)
    def test_no_hardware_acceptance_from_empty_attestations(self):
        errors = release.evaluate({'hardwareEvidence': {'tests': {}}}, 'production')
        for name in release.HARDWARE_TESTS:
            self.assertIn(f'hardware acceptance missing: {name}', errors)
        self.assertIn('explicit release approval reference missing', errors)
    def test_malformed_manifest_and_changed_test_artifact_are_blocked(self):
        self.assertTrue(release.evaluate([], 'production'))
        self.assertTrue(release.evaluate({'identifiers': []}, 'hardware-test'))
        errors = release.evaluate({'sourceCommit': 'a' * 40,
            'artifacts': {'app': {'sha256': 'current'}},
            'hardwareEvidence': {'sourceCommit': 'b' * 40, 'testedArtifactHashes': {'app': 'old'}}}, 'production')
        self.assertIn('hardware-tested source does not match candidate source', errors)
        self.assertIn('app: hardware-tested artifact differs from candidate', errors)
    def test_repository_profile_path_is_rejected(self):
        with self.assertRaises(ValueError): release.external_file(release.ROOT / '.env.example')
if __name__ == '__main__': unittest.main()
