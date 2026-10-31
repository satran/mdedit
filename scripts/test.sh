#!/bin/bash
# Runs the test suite and exits non-zero if anything fails or the build breaks.
#   scripts/test.sh                       everything
#   scripts/test.sh Class                 one test class
#   scripts/test.sh Class/testMethod      one test
# The full log is in build/test.log, results and coverage in build/TestResults.xcresult.
set -o pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "xcodegen is missing: brew install xcodegen"; exit 2; }
xcodegen generate >/dev/null || exit 2
mkdir -p build
rm -rf build/TestResults.xcresult

only=()
for t in "$@"; do only+=("-only-testing:MDEditTests/$t"); done

xcodebuild -project MDEdit.xcodeproj -scheme MDEdit -derivedDataPath build/DerivedData -configuration Debug \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -resultBundlePath build/TestResults.xcresult -enableCodeCoverage YES \
  test "${only[@]}" > build/test.log 2>&1
status=$?

# what went wrong, then the totals
grep -aE "error: |: error|Test Case .* failed|\*\* (BUILD|TEST) FAILED" build/test.log | grep -av "linkd.autoShortcut" | sed -E 's/^\/Users\/[^ ]*\/(Sources|Tests)\//\1\//' | sort -u | head -60
grep -aE "Executed [0-9]+ tests?, with" build/test.log | tail -1
if [ $status -eq 0 ]; then echo "PASS"; else echo "FAIL (log: build/test.log)"; fi
exit $status
