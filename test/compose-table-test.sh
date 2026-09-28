#!/bin/bash

# ComposeTable.js turns compose-dump output into symbol -> shortest sequence.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const compose = requireFromRoot('ComposeTable.js')

const dump = [
  '<Multi_key> <g> <a> : "α" U03B1 # GREEK SMALL LETTER ALPHA',
  '<Multi_key> <minus> <greater> : "→" U2192',
  '<Multi_key> <asciicircum> <asciicircum> <a> : "ᵃ"',
  '<Multi_key> <less> <equal> : "≤"',
  '<Multi_key> <equal> <less> : "≤"',
  '<Multi_key> <o> <o> : "°"',
  '<Multi_key> <d> <e> <g> : "°"',
  '<Multi_key> <space> <space> : "\\240"',
  '<Multi_key> <quotedbl> <a> : "\\"" ',
  '<dead_acute> <a> : "á"',
  '<Multi_key> <l> <l> : "ll"',
  'include "%L"',
  '',
].join('\n')

const parsed = compose.parse(dump)

assertEqual(parsed.bySymbol['α'], 'g a', 'letters render as themselves')
assertEqual(parsed.bySymbol['→'], '- >', 'keysyms render as the printable key')
assertEqual(parsed.bySymbol['ᵃ'], '^ ^ a', 'three-key sequences keep their order')
assert(parsed.bySymbol['≤'] === '< =' || parsed.bySymbol['≤'] === '= <', 'two sequences of equal length keep one of them')
assertEqual(parsed.bySymbol['°'], 'o o', 'the shorter of two sequences wins')
assertEqual(parsed.bySymbol[' '], '␣ ␣', 'octal escapes decode and space shows as a visible glyph')
assertEqual(parsed.bySymbol['"'], '" a', 'escaped quotes inside the result decode')
assertEqual(parsed.bySymbol['á'], undefined, 'sequences that do not start with Multi_key are ignored')
assertEqual(parsed.bySymbol['ll'], 'l l', 'multi-character results are kept')
assertEqual(parsed.count, 10, 'count is the number of distinct Multi_key sequences')

assertEqual(compose.keyGlyph('dead_grave'), 'grave', 'dead keys lose their prefix')
assertEqual(compose.keyGlyph('numbersign'), '#', 'known keysyms map to glyphs')
assertEqual(compose.keyGlyph('Greek_alpha'), 'Greek_alpha', 'unknown keysyms pass through')
assertEqual(compose.decodeString('a\\tb'), 'a\tb', 'tab escapes decode')
assertEqual(compose.decodeString('\\303\\251'), 'é', 'octal escapes are UTF-8 bytes, not one character per byte')
assertEqual(compose.decodeString('\\xc3\\xa9'), 'é', 'hex escapes decode the same way')
assertEqual(compose.decodeString('caf\\303\\251!'), 'café!', 'escaped bytes mix with plain text')
assertEqual(compose.decodeString('\\342\\202\\254'), '€', 'three-byte sequences decode')
assertEqual(compose.decodeString('\\360\\237\\230\\200'), '😀', 'four-byte sequences decode to one code point')
assertEqual(compose.decodeString('\\303'), 'Ã', 'a run that is not UTF-8 is read as Latin-1')
assertEqual(compose.decodeString('\\240'), '\u00a0', 'a Latin-1 table\'s no-break space still decodes')

assertDeepEqual(compose.parse(''), { bySymbol: {}, count: 0 }, 'empty input is an empty table')
assertDeepEqual(compose.parse('garbage without a colon'), { bySymbol: {}, count: 0 }, 'unparseable lines are skipped')

// Later definitions of the same sequence override earlier ones, as libX11 does.
const override = compose.parse('<Multi_key> <g> <a> : "α"\n<Multi_key> <g> <a> : "ɑ"\n')
assertEqual(override.bySymbol['ɑ'], 'g a', 'a later definition of a sequence wins')
assertEqual(override.bySymbol['α'], undefined, 'and the earlier symbol no longer claims it')
JS
