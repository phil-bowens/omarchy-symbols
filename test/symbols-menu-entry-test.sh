#!/bin/bash

# symbols-menu-entry is the only thing that touches the menu extension file:
# bounded read, refusals for anything but a plain file of ours, atomic write.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
ext="$HOME/.config/omarchy/extensions"
file="$ext/omarchy-menu.jsonc"
helper="$ROOT/symbols-menu-entry"
mkdir -p "$HOME"

run() { bash "$helper" "$@"; }
code() { set +e; bash "$helper" "$@" >/dev/null 2>&1; echo $?; set -e; }

# read
assert_equal "$(run read)" '' 'no extensions directory: read prints nothing'
assert_equal "$(code read)" '0' 'and exits 0'
assert '... and creates the directory for the write that follows' test -d "$ext"
printf '{\n  // hello\n}\n' >"$file"
assert_equal "$(run read)" "$(printf '{\n  // hello\n}')" 'a plain file is printed whole'
head -c $((1024 * 1024 + 1)) /dev/zero | tr '\0' 'x' >"$file"
assert_equal "$(code read)" '3' 'a file over 1 MiB is refused'
head -c $((1024 * 1024)) /dev/zero | tr '\0' 'x' >"$file"
assert_equal "$(run read | wc -c)" "$((1024 * 1024))" 'a file exactly at the cap is read'
rm -f "$file"; mkfifo "$file"
assert_equal "$(code read)" '3' 'a FIFO is refused, and the read does not hang'
rm -f "$file"; echo '{}' >"$tmp/elsewhere.jsonc"; ln -s "$tmp/elsewhere.jsonc" "$file"
assert_equal "$(code read)" '3' 'a symlink is refused even when its target is fine'
rm -f "$file"

# write
printf '{\n  "a": {"label":"A"}\n}\n' >"$file"; chmod 600 "$file"
printf '{\n  "b": {"label":"B"}\n}\n' | run write
assert_equal "$(cat "$file")" "$(printf '{\n  "b": {"label":"B"}\n}')" 'write replaces the file with stdin'
assert_equal "$(stat -c %a "$file")" '600' 'the existing mode is kept'
assert_equal "$(ls -A "$ext" | wc -l)" '1' 'no temp file is left behind'
assert_equal "$(printf '' | code write)" '3' 'an empty body is refused'
assert_equal "$(cat "$file")" "$(printf '{\n  "b": {"label":"B"}\n}')" '... and the file is untouched'
assert_equal "$(head -c $((1024 * 1024 + 5)) /dev/zero | code write)" '3' 'an oversized body is refused'
assert_equal "$(cat "$file")" "$(printf '{\n  "b": {"label":"B"}\n}')" '... and the file is untouched'
rm -f "$file"; ln -s "$tmp/elsewhere.jsonc" "$file"
assert_equal "$(echo '{"x":1}' | code write)" '3' 'a symlinked file is not written through'
assert_equal "$(cat "$tmp/elsewhere.jsonc")" '{}' '... and its target is untouched'
rm -f "$file"
echo '{"x":1}' | run write
assert_equal "$(cat "$file")" '{"x":1}' 'write creates the file when there is none'
assert_equal "$(stat -c %a "$file")" '644' '... with the usual mode'
rm -rf "$ext"; mkdir -p "$tmp/other"; ln -s "$tmp/other" "$ext"
assert_equal "$(echo '{"y":1}' | code write)" '3' 'a symlinked extensions directory is refused'
assert '... and nothing lands in its target' test -z "$(ls -A "$tmp/other")"
rm -f "$ext"
assert_equal "$( (sleep 7) | code write)" '124' 'a writer that never finishes is cut off by the timeout'

# mark
run mark
assert 'mark creates the marker under XDG_STATE_HOME' test -f "$XDG_STATE_HOME/omarchy-symbols/menu-entry-offered"
assert_equal "$(code bogus)" '2' 'an unknown subcommand is an error'
