import json
import subprocess
import sys

major = int(sys.argv[1])
runtimes = json.loads(subprocess.check_output(["xcrun","simctl","list","runtimes","--json"]))["runtimes"]
eligible = [r for r in runtimes if r.get("isAvailable") and r["name"].startswith("iOS ") and int(r["version"].split(".")[0]) == major]
if not eligible:
    raise SystemExit(f"No available iOS {major} runtime; refusing to test another OS")
runtime = max(eligible,key=lambda r:tuple(int(n) for n in r["version"].split(".")))
udid = subprocess.check_output(["xcrun","simctl","create",f"CampusLens-iOS{major}","com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",runtime["identifier"]],text=True).strip()
print(udid)
