#!/bin/bash

# symbols.js is generated; these checks are what the overlay assumes of it.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const vm = require('vm')
const context = {}
vm.runInNewContext(fs.readFileSync(path.join(root, 'symbols.js'), 'utf8'), context)
const { SYMBOLS, GROUPS, GROUP_KEYS } = context

assert(Array.isArray(SYMBOLS) && SYMBOLS.length >= 400, `symbols.js holds the curated set (${SYMBOLS.length} entries)`)

const seen = new Set()
let ok = true
for (const s of SYMBOLS) {
  if (!(typeof s.e === 'string' && s.e.length > 0)) ok = false
  if (!(typeof s.n === 'string' && s.n.length > 0)) ok = false
  if (!(typeof s.s === 'string' && s.s.length > 0)) ok = false
  if (!(typeof s.g === 'string' && GROUPS.includes(s.g))) ok = false
  if (!(typeof s.k === 'string' && s.k === s.k.toLowerCase())) ok = false
  if (!s.k.includes(s.n.toLowerCase())) ok = false
  // A composed result such as °C has no single code point to search by.
  if ([...s.e].length === 1 && !/u\+[0-9a-f]{4,6}/.test(s.k)) ok = false
  seen.add(s.e)
}
assert(ok, 'every entry has a symbol, a name, a sequence, a known group, and lowercase keywords with its name and, for single characters, its code point')
assertEqual(seen.size, SYMBOLS.length, 'no symbol appears twice')

assert(GROUPS.length >= 10 && new Set(GROUPS).size === GROUPS.length, 'groups are distinct')
const letters = Object.values(GROUP_KEYS)
assertEqual(new Set(letters).size, letters.length, 'chip letters are distinct')
assert(letters.every(l => /^[a-y]$/.test(l)), 'chip letters leave 0 (All) and z (Unicode) to the overlay')
assert(Object.keys(GROUP_KEYS).every(g => GROUPS.includes(g)), 'every chip letter belongs to a group that exists')
assertEqual(GROUP_KEYS.Greek, 'g', 'Greek keeps its compose prefix as its chip letter')
assertEqual(GROUP_KEYS.Math, 'h', 'Math keeps its compose prefix as its chip letter')

const alpha = SYMBOLS.find(s => s.e === 'α')
assert(alpha && alpha.g === 'Greek' && alpha.s === 'g a', 'alpha is Greek with the g a sequence')
JS
