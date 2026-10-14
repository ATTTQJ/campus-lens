"""Package an unsigned device archive with POSIX permissions and symlinks intact."""
from pathlib import Path
import plistlib
import stat
import sys
import zipfile

def package(archive,output):
    apps = list((Path(archive)/"Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Expected exactly one device .app in archive")
    app = apps[0]
    with (app/"Info.plist").open("rb") as f:
        info = plistlib.load(f)
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Archive is not an iPhoneOS device build")
    executable = app/info["CFBundleExecutable"]
    if not executable.is_file() or not (executable.stat().st_mode & stat.S_IXUSR):
        raise ValueError("Device executable missing or not executable")
    if (app/"_CodeSignature").exists() or (app/"embedded.mobileprovision").exists():
        raise ValueError("Archive unexpectedly contains signing material")
    output = Path(output); output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,"w",compression=zipfile.ZIP_DEFLATED) as z:
        for path in [app]+sorted(app.rglob("*")):
            entry = "Payload/"+path.relative_to(app.parent).as_posix()
            mode = path.lstat().st_mode
            if path.is_symlink():
                zi = zipfile.ZipInfo(entry); zi.create_system = 3; zi.external_attr = mode << 16
                z.writestr(zi,str(path.readlink()).encode())
            elif path.is_dir():
                zi = zipfile.ZipInfo(entry+"/"); zi.create_system = 3; zi.external_attr = (mode << 16)|0x10
                z.writestr(zi,b"")
            else:
                z.write(path,entry)
    with zipfile.ZipFile(output) as z:
        exec_entry = z.getinfo("Payload/"+app.name+"/"+info["CFBundleExecutable"])
        if not ((exec_entry.external_attr >> 16) & stat.S_IXUSR):
            raise ValueError("IPA lost executable permission")
    print(f"Unsigned IPA: {output}")

if __name__ == "__main__":
    package(sys.argv[1],sys.argv[2])
