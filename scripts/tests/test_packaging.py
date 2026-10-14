from pathlib import Path
import importlib.util
import os
import plistlib
import stat
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("package_ipa",Path(__file__).resolve().parents[1]/"package_ipa.py")
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class PackagingTests(unittest.TestCase):
    def create_app(self,temporary):
        archive = Path(temporary)/"App.xcarchive"
        app = archive/"Products/Applications/CampusLens.app"
        app.mkdir(parents=True)
        (app/"Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable":"CampusLens","CFBundleSupportedPlatforms":["iPhoneOS"]}))
        executable = app/"CampusLens"; executable.write_bytes(b"test-device-executable")
        executable.chmod(0o755)
        return archive,app
    @unittest.skipIf(os.name == "nt","POSIX executable modes are tested by Linux/macOS CI")
    def test_payload_executable_and_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive,app = self.create_app(temporary)
            (app/"Link").symlink_to("CampusLens")
            output = Path(temporary)/"unsigned.ipa"
            module.package(archive,output)
            with zipfile.ZipFile(output) as z:
                self.assertTrue(z.getinfo("Payload/CampusLens.app/CampusLens").external_attr >> 16 & stat.S_IXUSR)
                self.assertTrue(stat.S_ISLNK(z.getinfo("Payload/CampusLens.app/Link").external_attr >> 16))
                self.assertEqual(z.read("Payload/CampusLens.app/Link"),b"CampusLens")
    def test_archive_layout_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError): module.package(temporary,Path(temporary)/"out.ipa")
    def test_simulator_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive,app = self.create_app(temporary)
            (app/"Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable":"CampusLens","CFBundleSupportedPlatforms":["iPhoneSimulator"]}))
            with self.assertRaises(ValueError): module.package(archive,Path(temporary)/"out.ipa")

if __name__ == "__main__": unittest.main()
