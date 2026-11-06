#!/bin/bash
# Static checks on the template engine's source (plan 006). Usage: audit-templates.sh [source dir, default Sources/MDEdit]
# These rules look for the names of write, process and network APIs. They are a tripwire, not a proof that the engine cannot write:
# the guarantee is that the template grammar has no construct that writes.
dir="${1:-$(cd "$(dirname "$0")/.." && pwd)/Sources/MDEdit}"
fail=0
bad() { echo "AUDIT FAIL: $1"; fail=1; }

templates="$dir/Templates"
safepath="$dir/Model/SafePath.swift"
if [ ! -d "$templates" ]; then echo "skip: no Templates folder"; exit 0; fi
files=$(find "$templates" -name '*.swift'; [ -f "$safepath" ] && echo "$safepath")

# 1. No write, delete, move, copy, link, attribute change, coordination, stream, low-level file, process, network or workspace API.
names='\.write\(|write\(to|createFile|removeItem|trashItem|moveItem|copyItem|replaceItem|createDirectory|createSymbolicLink|linkItem|setAttributes|FileHandle\(forWriting|FileHandle\(forUpdating|NSFileCoordinator|OutputStream|fopen\(|(^|[^.A-Za-z_])unlink\(|(^|[^.A-Za-z_])rename\(|(^|[^.A-Za-z_])truncate\(|posix_spawn|NSTask|(^|[^.A-Za-z_])Process\(|URLSession|URLConnection|NWConnection|NSWorkspace|import Network'
# shellcheck disable=SC2086
hits=$(grep -nE "$names" $files 2>/dev/null)
[ -n "$hits" ] && { echo "$hits"; bad "template source uses a write, process or network API"; }

# 2. Only TemplateSources.swift and SafePath.swift may touch the file system.
for f in $(find "$templates" -name '*.swift'); do
  [ "$(basename "$f")" = "TemplateSources.swift" ] && continue
  hits=$(grep -nE 'FileManager|Data\(contentsOf|String\(contentsOf|FileHandle|contentsOfDirectory' "$f")
  [ -n "$hits" ] && { echo "$f: $hits"; bad "file access outside TemplateSources.swift"; }
done

[ $fail -eq 0 ] && echo "ok: template source rules hold"
exit $fail
