#!/bin/bash
# Proves that audit-templates.sh fails when a violation is planted in a copy of the template sources.
cd "$(dirname "$0")/.." || exit 1
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fresh() {
  rm -rf "$tmp/src"; mkdir -p "$tmp/src/Model"
  cp -R Sources/MDEdit/Templates "$tmp/src/Templates"
  cp Sources/MDEdit/Model/SafePath.swift "$tmp/src/Model/SafePath.swift"
}
expect_fail() { # description, file, line to append
  fresh
  echo "$3" >> "$tmp/src/$2"
  if scripts/audit-templates.sh "$tmp/src" >/dev/null 2>&1; then echo "SELFTEST FAIL: $1 was not caught"; fail=1; fi
}

fresh
scripts/audit-templates.sh "$tmp/src" >/dev/null 2>&1 || { echo "SELFTEST FAIL: the clean copy does not pass"; fail=1; }
expect_fail "removeItem in the parser" Templates/TemplateParser.swift 'let _ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/x"))'
expect_fail "FileManager in the values file" Templates/TemplateValue.swift 'let _ = FileManager.default'
expect_fail "removeItem in the sources file" Templates/TemplateSources.swift 'let _ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/x"))'
expect_fail "a process in the evaluator" Templates/TemplateEvaluator.swift 'let _ = Process()'
expect_fail "a write in SafePath" Model/SafePath.swift 'let _ = try? Data().write(to: URL(fileURLWithPath: "/x"))'
expect_fail "a connection in the guard-to-be" Templates/TemplateLimits.swift 'import Network'

[ $fail -eq 0 ] && echo "ok: the template audit catches planted violations"
exit $fail
