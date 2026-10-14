#!/bin/bash
set -euo pipefail
major="${1:?iOS major is required}"
mode="${2:-test}"
mkdir -p artifacts
xcodebuild -version | tee artifacts/xcode-version.txt
xcodebuild -showsdks > artifacts/sdks.txt
git rev-parse HEAD > artifacts/commit.txt
python3 scripts/generate_project.py
git diff --exit-code -- CampusLens.xcodeproj
swift test 2>&1 | tee artifacts/core-tests.log
udid=$(python3 scripts/select_simulator.py "$major")
printf '%s\n' "$udid" > artifacts/simulator.txt
# Type-check and compile before the cold simulator boot. A source error should
# be reported immediately rather than after several minutes of OS migration.
xcodebuild build-for-testing -project CampusLens.xcodeproj -scheme CampusLens -configuration Debug \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee artifacts/simulator-build.log
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcodebuild test -project CampusLens.xcodeproj -scheme CampusLens -configuration Debug \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/DerivedData \
  -resultBundlePath artifacts/iOS-tests.xcresult -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tee artifacts/simulator-tests.log
if [[ "$mode" == "archive" ]]; then
  xcodebuild archive -project CampusLens.xcodeproj -scheme CampusLens -configuration Release \
    -destination 'generic/platform=iOS' -archivePath build/CampusLens.xcarchive \
    -derivedDataPath build/DeviceData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
    2>&1 | tee artifacts/archive.log
  python3 scripts/package_ipa.py build/CampusLens.xcarchive artifacts/CampusLens-unsigned.ipa
  shasum -a 256 artifacts/CampusLens-unsigned.ipa > artifacts/SHA256SUMS.txt
fi
python3 - "$major" "$mode" <<'PY'
import json,os,subprocess,sys
from pathlib import Path
Path('artifacts/version.json').write_text(json.dumps({
    'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'iosTestMajor':int(sys.argv[1]),'mode':sys.argv[2],
    'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
    'run':os.environ.get('GITHUB_RUN_ID'),'unsigned':True,'realDeviceValidated':False,
    'status':'Automated tests passed; real camera validation is pending'
},ensure_ascii=False,indent=2)+'\n')
PY
