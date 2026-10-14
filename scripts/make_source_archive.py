"""Package only Git-visible source files, honoring .gitignore."""
from pathlib import Path
import hashlib
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
paths = subprocess.check_output(["git","ls-files","--cached","--others","--exclude-standard","-z"],cwd=root).decode("utf-8").split("\0")
output = root/"artifacts/CampusLens-source.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output,"w",zipfile.ZIP_DEFLATED) as z:
    for name in sorted(set(paths)):
        if not name: continue
        file = root/name
        if file.is_file(): z.write(file,"campus-lens/"+name)
digest = hashlib.sha256(output.read_bytes()).hexdigest()
(output.parent/"CampusLens-source.sha256").write_text(digest+"  CampusLens-source.zip\n",encoding="utf-8")
print(f"Source archive: {output}\nSHA256: {digest}")
