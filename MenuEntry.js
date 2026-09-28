// Offers a "Symbols" row in the Omarchy menu, next to Emoji under Trigger,
// by adding one entry to ~/.config/omarchy/extensions/omarchy-menu.jsonc.
// Pure text in, text out, so the tests can run it under node. The caller
// writes the result and records that the offer was made, so a row the user
// deletes stays deleted.

var KEY = "trigger.symbols"
var MAX_BYTES = 1048576

// The shell's own reading of the file: whole-line // comments and trailing
// commas are dropped, nothing else.
function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

function parseObject(raw) {
  var stripped = stripJsonc(raw)
  if (stripped.trim() === "") return {}
  var parsed
  try { parsed = JSON.parse(stripped) } catch (e) { return null }
  return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null
}

function block(pluginId) {
  return '  "' + KEY + '": {\n' +
    '    "icon": "∑",\n' +
    '    "label": "Symbols",\n' +
    '    "aliases": ["symbols", "symbol", "greek", "math", "arrows", "compose"],\n' +
    '    "description": "Search and insert STEM symbols, with the compose sequence that types them",\n' +
    '    "action": "omarchy-shell shell toggle ' + pluginId + '"\n' +
    '  }'
}

// The new file text, or null when nothing should be written: the row is
// already there, the file is not a JSONC object, it is too large to trust,
// or the result would not read back with every existing entry intact.
function withEntry(raw, pluginId) {
  raw = String(raw || "")
  if (raw.length > MAX_BYTES) return null
  if (raw.indexOf('"' + KEY + '"') !== -1) return null
  var before = parseObject(raw)
  if (before === null) return null
  if (Object.prototype.hasOwnProperty.call(before, KEY)) return null

  var next
  if (stripJsonc(raw).trim() === "") {
    // Empty, or comments only: keep whatever comments there are above a new object.
    var head = raw.trim() === "" ? "" : raw.replace(/\s+$/, "") + "\n"
    next = head + "{\n" + block(pluginId) + "\n}\n"
  } else {
    // Insert right after the object's opening brace, skipping comment lines,
    // so a comment sitting after the last entry cannot end up carrying the
    // comma. The shell tolerates the trailing comma an empty object gets.
    var lines = raw.split("\n")
    var offset = 0
    var at = -1
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!/^\s*\/\//.test(line)) {
        var brace = line.indexOf("{")
        if (brace !== -1) { at = offset + brace; break }
      }
      offset += line.length + 1
    }
    if (at === -1) return null
    next = raw.slice(0, at + 1) + "\n" + block(pluginId) + "," + raw.slice(at + 1)
  }

  var after = parseObject(next)
  if (after === null || !after[KEY]) return null
  for (var key in before) {
    if (!Object.prototype.hasOwnProperty.call(after, key)) return null
    if (JSON.stringify(after[key]) !== JSON.stringify(before[key])) return null
  }
  if (Object.keys(after).length !== Object.keys(before).length + 1) return null
  return next
}

if (typeof module !== "undefined") module.exports = { withEntry: withEntry, stripJsonc: stripJsonc, KEY: KEY }
