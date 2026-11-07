import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('preview_bundle', Path(__file__).resolve().parents[1] / 'assemble-legacy-preview.py')
preview = importlib.util.module_from_spec(spec); spec.loader.exec_module(preview)
class PreviewBundle(unittest.TestCase):
    def test_bundle_is_separate_and_has_no_feed_or_extension(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); binary = root / 'input'; binary.write_bytes(b'compile-fixture')
            output = preview.assemble(binary, root / 'Preview.app')
            info = plistlib.loads((output / 'Contents/Info.plist').read_bytes())
            self.assertEqual(info['CFBundleIdentifier'], 'com.kiwimartin.symphonymaestro.preview')
            self.assertNotIn('SUFeedURL', info)
            self.assertFalse((output / 'Contents/Library/SystemExtensions').exists())
            self.assertEqual((output / 'Contents/MacOS/LegacyMaestroPreview').read_bytes(), b'compile-fixture')
            with self.assertRaises(ValueError): preview.assemble(binary, output)
    def test_missing_binary_does_not_create_fake_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError): preview.assemble(root / 'missing', root / 'Preview.app')
            self.assertFalse((root / 'Preview.app').exists())
if __name__ == '__main__': unittest.main()
