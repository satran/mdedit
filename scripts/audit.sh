#!/bin/bash
# Static checks on the app's security posture. Run after `make app`.
cd "$(dirname "$0")/.."
fail=0
bad() { echo "AUDIT FAIL: $1"; fail=1; }
ok()  { echo "ok: $1"; }

# 1. Entitlements are exactly the ones the app needs.
ALLOWED="com.apple.security.app-sandbox com.apple.security.files.bookmarks.app-scope com.apple.security.files.user-selected.read-write com.apple.security.network.client com.apple.security.network.server"
found=$(/usr/libexec/PlistBuddy -c "Print" MDEdit.entitlements | grep -E "^\s+com\.apple" | awk '{print $1}')
for e in $found; do
  case " $ALLOWED " in *" $e "*) ;; *) bad "unexpected entitlement $e";; esac
done
for e in $ALLOWED; do echo "$found" | grep -q "^$e$" || bad "missing entitlement $e"; done
[ $fail -eq 0 ] && ok "entitlements are the expected five (sandbox, user-selected files, bookmarks, network client, network server for agent access)"

# 2. The built app really is sandboxed.
if [ -d build/MDEdit.app ]; then
  tmp=$(mktemp)
  codesign -d --entitlements :- build/MDEdit.app > "$tmp" 2>/dev/null
  built=$(/usr/libexec/PlistBuddy -c "Print" "$tmp" 2>/dev/null | grep -E "^\s+com\.apple" | awk '{print $1}')
  rm -f "$tmp"
  echo "$built" | grep -q "^com.apple.security.app-sandbox$" && ok "built app is sandboxed" || bad "built app is not sandboxed"
  for e in $built; do
    case " $ALLOWED " in *" $e "*) ;; *) bad "built app has an unexpected entitlement: $e";; esac
  done
else
  echo "skip: build/MDEdit.app not built (make app)"
fi

# 3. No loosened transport security, no JavaScript switched on, no unsafe APIs.
grep -q "NSAllowsArbitraryLoads" Sources/MDEdit/Info.plist && bad "Info.plist allows arbitrary loads"
grep -rn "allowsContentJavaScript *= *true\|javaScriptEnabled *= *true" Sources && bad "JavaScript enabled in a web view"
# the app starts no program at all
grep -rnE "NSAppleScript|Process\(\)|NSTask|popen\(|execv|fork\(\)|posix_spawn|(^|[^.A-Za-z])system\(" Sources && bad "runs external programs"
grep -rn "loadFileURL\|allowFileAccessFromFileURLs\|NSWorkspace.shared.open(.*launch" Sources && bad "web view file access or launching"
grep -rn "WKWebView(" Sources | grep -v "configuration" && bad "WKWebView created without a configuration (JavaScript would be on)"
# every call that opens something must be one of the vetted ones below (links go through LinkPolicy first)
grep -rn "NSWorkspace.shared.open(" Sources | grep -v "case \.openWeb\|case \.openFile\|LinkPolicy.isProgram(node.url)\|else { NSWorkspace.shared.open(node.url) }\|LinkPolicy.webSchemes" | while read -r l; do echo "REVIEW: $l"; done
[ $fail -eq 0 ] && ok "no unsafe API patterns"

# 3b. The one listening socket: only MCPServer may open one, only on loopback, and the app has no URL scheme.
grep -rln "NWListener" Sources | grep -v "Agents/MCPServer.swift" | while read -r l; do echo "NWListener outside MCPServer: $l"; done | grep . && bad "a listener is created outside Agents/MCPServer.swift"
grep -rn "0\.0\.0\.0\|::\"" Sources | grep -v "^Sources/MDEdit/Resources" | grep -i "listen\|bind\|endpoint" && bad "something may listen on all interfaces"
if [ -f Sources/MDEdit/Agents/MCPServer.swift ]; then
  grep -q "requiredLocalEndpoint" Sources/MDEdit/Agents/MCPServer.swift || bad "MCPServer must bind with requiredLocalEndpoint (loopback only)"
fi
grep -q "CFBundleURLTypes" Sources/MDEdit/Info.plist && bad "Info.plist declares a URL scheme"
[ $fail -eq 0 ] && ok "listener rules hold (MCPServer only, loopback, no URL scheme)"

# 3c. The template engine only reads (plan 006): its source is checked for write, process and network APIs, and the checks themselves are tested.
scripts/audit-templates.sh || bad "template source rules"
scripts/audit-templates-selftest.sh || bad "template audit self-test"

# 4. No force-try or fatalError in the app outside of constant regex setup.
n=$(grep -rn "fatalError\|try!" Sources | grep -v "NSRegularExpression(pattern" | wc -l | tr -d ' ')
[ "$n" = "0" ] && ok "no fatalError / try! outside constant regexes" || { bad "$n uses of fatalError/try!"; grep -rn "fatalError\|try!" Sources | grep -v "NSRegularExpression(pattern"; }

# 5. Only the vetted fonts are bundled (licences present).
ls Sources/MDEdit/Resources/Fonts/OFL-*.txt >/dev/null 2>&1 && ok "font licences present" || bad "font licences missing"

if [ $fail -eq 0 ]; then echo "AUDIT PASS"; else echo "AUDIT FAILED"; fi
exit $fail
