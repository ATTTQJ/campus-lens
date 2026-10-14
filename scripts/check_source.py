"""Portable source/package checks; not an iOS compiler or a substitute for Swift tests."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
files = [p for p in root.rglob("*") if p.is_file() and ".git" not in p.parts and "__pycache__" not in p.parts and "build" not in p.parts and "artifacts" not in p.parts and ".build" not in p.parts]
for path in files:
    if path.suffix.lower() in {".dng",".ipa",".p12",".mobileprovision"}:
        raise AssertionError(f"Private photo/signing/build artifact in source: {path}")
    if path.suffix in {".swift",".yml",".md",".py",".sh"}:
        text = path.read_text(encoding="utf-8")
        assert not re.search(r"sk-[A-Za-z0-9_-]{20,}",text),f"Potential API credential: {path}"
        assert not re.search(r"gh[pousr]_[A-Za-z0-9]{20,}",text),f"Potential GitHub credential: {path}"
for file in ["App/Info.plist","App/PrivacyInfo.xcprivacy"]:
    with (root/file).open("rb") as stream:
        plistlib.load(stream)
scheme = ET.parse(root/"CampusLens.xcodeproj/xcshareddata/xcschemes/CampusLens.xcscheme")
assert len(scheme.findall(".//TestableReference")) == 2
project = (root/"CampusLens.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
for path in files:
    if path.suffix == ".swift" and "Sources" not in path.parts and path.name != "Package.swift":
        assert path.relative_to(root).as_posix() in project,f"Swift file excluded from project: {path}"
assert 'IPHONEOS_DEPLOYMENT_TARGET = "26.0"' in project
assert 'SWIFT_VERSION = "6.0"' in project
json.loads((root/"App/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text())
print(f"Source integrity checks passed ({len(files)} files). Swift/iOS compilation still requires CI.")
