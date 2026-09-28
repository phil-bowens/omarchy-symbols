#!/bin/bash

# MenuEntry.js adds one row to the Omarchy menu extension file and refuses
# to touch anything it cannot read back intact.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const menu = requireFromRoot('MenuEntry.js')
const id = 'io.github.phil-bowens.symbols'
const parse = s => JSON.parse(menu.stripJsonc(s))

// The template Omarchy ships: a comment header and no entries.
const template = '{\n  // Extend the Quickshell Omarchy menu with JSONC.\n  //\n  // Examples:\n  // "personal": {"icon":"","label":"Personal"},\n}\n'
let out = menu.withEntry(template, id)
assert(out !== null, 'the shipped template gets the row')
assertEqual(parse(out)['trigger.symbols'].action, 'omarchy-shell shell toggle ' + id, 'the row toggles the plugin by its id')
assert(out.indexOf('// Extend the Quickshell Omarchy menu') !== -1, 'the header comment is kept')

// A file with entries and a comment after the last one.
const busy = '{\n  "personal": {"icon":"","label":"Personal"},\n  "personal.notes": {"icon":"","label":"Notes","action":"nvim"}\n  // trailing note\n}\n'
out = menu.withEntry(busy, id)
assert(out !== null, 'a file with entries and a trailing comment gets the row')
const after = parse(out)
assertDeepEqual(after['personal.notes'], { icon: '', label: 'Notes', action: 'nvim' }, 'existing entries are untouched')
assertEqual(Object.keys(after).length, 3, 'exactly one entry was added')

// Idempotent and respectful of the user's own version of the row.
assertEqual(menu.withEntry(out, id), null, 'a file that already has the row is left alone')
assertEqual(menu.withEntry('{ "trigger.symbols": {"label":"Mine","action":"true"} }', id), null, 'a hand-written row is left alone')

// Odd inputs never produce a write.
assertEqual(menu.withEntry('[1, 2]', id), null, 'an array is not a menu file')
assertEqual(menu.withEntry('{ "broken": ', id), null, 'unparseable text is left alone')
assertEqual(menu.withEntry('x'.repeat(2 * 1024 * 1024), id), null, 'an oversized file is left alone')
out = menu.withEntry('// only comments\n', id)
assert(out.indexOf('// only comments\n{') === 0, 'a comment-only file keeps its comment above a new object')
assert(parse(out)['trigger.symbols'] !== undefined, 'and gains the row')
assert(parse(menu.withEntry('', id))['trigger.symbols'] !== undefined, 'an empty file becomes an object with the row')
assert(parse(menu.withEntry('{}', id))['trigger.symbols'] !== undefined, 'an empty object gets the row')

// One-line objects survive too.
out = menu.withEntry('{ "a": {"label":"A"} }', id)
assertDeepEqual(parse(out).a, { label: 'A' }, 'a one-line object keeps its entry')
assert(parse(out)['trigger.symbols'] !== undefined, 'and gains the row')
JS
