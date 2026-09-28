#!/bin/bash

# symbols-insert pastes through a foreground wl-copy, then leaves the symbol
# on both selections.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export FAKE_LOG="$tmp/log"

cat >"$tmp/bin/wl-copy" <<'FAKE'
#!/bin/bash
echo "wl-copy $* <$(cat)>" >>"$FAKE_LOG"
if [[ " $* " == *" --foreground "* ]]; then sleep 5; fi
FAKE
cat >"$tmp/bin/wtype" <<'FAKE'
#!/bin/bash
echo "wtype $*" >>"$FAKE_LOG"
FAKE
cat >"$tmp/bin/setsid" <<'FAKE'
#!/bin/bash
[[ $1 == -f ]] && shift
echo "setsid" >>"$FAKE_LOG"
exec "$@"
FAKE
chmod +x "$tmp/bin/"*

bash "$ROOT/symbols-insert" "α"
sleep 0.3

assert_equal "$(sed -n 1p "$FAKE_LOG")" 'wl-copy --type text/plain --foreground <α>' 'the paste is served by a foreground wl-copy with an explicit text type'
assert_equal "$(sed -n 2p "$FAKE_LOG")" 'wtype -M shift -k Insert -m shift' 'Shift+Insert is typed after the copy'
assert 'the symbol is re-offered on the clipboard afterward' grep -q '^wl-copy --type text/plain <α>$' "$FAKE_LOG"
assert 'and on the primary selection' grep -q '^wl-copy --primary --type text/plain <α>$' "$FAKE_LOG"
assert_equal "$(grep -c '^setsid$' "$FAKE_LOG")" '2' 'the two re-offers are detached'

: >"$FAKE_LOG"
bash "$ROOT/symbols-insert" ""
assert_equal "$(wc -c <"$FAKE_LOG" | tr -d ' ')" '0' 'an empty symbol does nothing'
