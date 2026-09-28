#!/bin/bash

# compose-dump follows ~/.XCompose and its includes the way libX11 does.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
# The real session may point XCOMPOSEFILE at the user's own table.
unset XCOMPOSEFILE
mkdir -p "$HOME/extra"

cat >"$HOME/extra/stem.XCompose" <<'X'
# a richer table
<Multi_key> <g> <a> : "α" U03B1
<Multi_key> <asciicircum> <asciicircum> <a> : "ᵃ"
include "%H/extra/loop.XCompose"
X
cat >"$HOME/extra/loop.XCompose" <<'X'
include "%H/extra/stem.XCompose"
<Multi_key> <l> <p> : "loop"
X
cat >"$HOME/.XCompose" <<'X'
include "%H/extra/stem.XCompose"
<Multi_key> <o> <k> : "ok"
<dead_acute> <a> : "not a multi key line"
X

out="$tmp/out"
bash "$ROOT/compose-dump" >"$out"
assert 'lines from the start file are printed' grep -q '<Multi_key> <o> <k> : "ok"' "$out"
assert 'lines from an included file are printed' grep -q '"α"' "$out"
assert 'an include of an include is followed' grep -q '"loop"' "$out"
assert_equal "$(grep -c '"α"' "$out")" '1' 'a file included twice through a cycle is dumped once'
assert_equal "$(grep -c 'dead_acute' "$out")" '0' 'lines without Multi_key are left out'

bash "$ROOT/compose-dump" "$HOME/extra/stem.XCompose" >"$out"
assert_equal "$(grep -c '"ok"' "$out")" '0' 'an explicit file argument is honored'

if [[ -f /usr/share/X11/locale/compose.dir ]]; then
  printf 'include "%%L"\n<Multi_key> <z> <z> : "zz"\n' >"$HOME/.XCompose"
  bash "$ROOT/compose-dump" >"$out"
  assert '%L brings in the system table' test "$(grep -c Multi_key "$out")" -gt 100
  assert 'and the start file still contributes' grep -q '"zz"' "$out"
  rm "$HOME/.XCompose"
  bash "$ROOT/compose-dump" >"$out"
  assert 'without a compose file the system table alone is dumped' test "$(grep -c Multi_key "$out")" -gt 100
else
  pass '%L expansion skipped: no X11 locale tables here # SKIP'
fi


# --- bounds: special files are skipped, oversized files are skipped, output is capped ---
mkfifo "$HOME/extra/pipe.XCompose"
truncate -s 9M "$HOME/extra/huge.XCompose"
printf '<Multi_key> <h> <g> : "huge"\n' >>"$HOME/extra/huge.XCompose"
awk 'BEGIN { for (i = 0; i < 100010; i++) printf "<Multi_key> <m> <%d> : \"m\"\n", i }' >"$HOME/extra/many.XCompose"
printf 'include "%%H/extra/pipe.XCompose"\ninclude "%%H/extra/huge.XCompose"\n<Multi_key> <a> <b> : "after"\n' >"$HOME/.XCompose"
bash "$ROOT/compose-dump" >"$out" 2>"$tmp/err"
assert 'an included FIFO is skipped and the dump still finishes' grep -q '"after"' "$out"
assert_equal "$(grep -c '"huge"' "$out")" '0' 'a file over the size cap is not read'
assert 'the skipped file is named on stderr' grep -q 'huge.XCompose' "$tmp/err"
bash "$ROOT/compose-dump" "$HOME/extra/many.XCompose" >"$out"
assert_equal "$(wc -l <"$out" | tr -d ' ')" '100000' 'output stops at the line cap'
