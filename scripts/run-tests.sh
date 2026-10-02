#!/bin/bash
set -euo pipefail

task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$task_root"
mkdir -p build/test-results
run_directory=$(mktemp -d "$task_root/build/test-results/run.XXXXXX")
simulator_id=""

cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

xcrun simctl list devices available --json > "$run_directory/available-simulators.json"
selection=$(python3 - "$run_directory/available-simulators.json" <<'PY'
import json
import re
import sys

devices = json.load(open(sys.argv[1]))["devices"]
candidates = []
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(n) for n in re.findall(r"\d+", runtime.split(".iOS-")[1]))
    for device in entries:
        device_type = device.get("deviceTypeIdentifier", "")
        if device.get("isAvailable") and ".iPhone-" in device_type:
            candidates.append((version, device_type, runtime))
if not candidates:
    sys.exit("No available iPhone simulator. Install an iOS Simulator runtime in Xcode.")
_, device_type, runtime = max(candidates)
print(device_type, runtime)
PY
)
read -r device_type runtime_id <<< "$selection"
simulator_id=$(xcrun simctl create "Castify Regression Tests $$" "$device_type" "$runtime_id")
printf 'Testing on %s (%s), runtime %s\nResults: %s\n' "$device_type" "$simulator_id" "$runtime_id" "$run_directory"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b | tee "$run_directory/simulator-boot.log"

xcodebuild \
  -project Podcasts.xcodeproj \
  -scheme Podcasts \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$run_directory/Tests.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  SENTRY_DSN= \
  test 2>&1 | tee "$run_directory/xcodebuild.log"
