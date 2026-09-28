// Turns the output of compose-dump into a map from symbol to the shortest
// compose sequence that produces it, rendered as the keys a person would
// press: "g a", "- >", "^ ^ a". Later definitions override earlier ones for
// the same sequence, as the compose machinery itself does.

var GLYPH = {
  asciicircum: "^", underscore: "_", minus: "-", greater: ">", less: "<",
  equal: "=", plus: "+", asterisk: "*", slash: "/", colon: ":", period: ".",
  comma: ",", apostrophe: "'", quotedbl: "\"", exclam: "!", question: "?",
  parenleft: "(", parenright: ")", bracketleft: "[", bracketright: "]",
  braceleft: "{", braceright: "}", asciitilde: "~", grave: "`", bar: "|",
  backslash: "\\", dollar: "$", percent: "%", ampersand: "&", at: "@",
  numbersign: "#", semicolon: ";", space: "␣"
}

var LINE = /^\s*((?:<[^>]+>\s*)+):\s*"((?:\\.|[^"\\])*)"/

function keyGlyph(name) {
  if (GLYPH[name] !== undefined) return GLYPH[name]
  if (name.indexOf("dead_") === 0) return name.slice(5)
  return name
}

// Escaped bytes in a compose result are the table's own encoding: a UTF-8
// table writes é as "\303\251" (octal) or "\xc3\xa9" (hex), and an old
// Latin-1 table writes a no-break space as a bare "\240". Collect each run
// of escaped bytes, read it as UTF-8, and fall back to Latin-1 when the run
// is not valid UTF-8.
function utf8Decode(bytes) {
  var out = ""
  var i = 0
  while (i < bytes.length) {
    var b = bytes[i]
    var n = b < 0x80 ? 0 : b >= 0xf0 && b <= 0xf4 ? 3 : b >= 0xe0 ? 2 : b >= 0xc2 ? 1 : -1
    if (n < 0 || i + n >= bytes.length + (n === 0 ? 1 : 0)) return null
    var cp = n === 0 ? b : n === 1 ? (b & 0x1f) : n === 2 ? (b & 0x0f) : (b & 0x07)
    for (var j = 1; j <= n; j++) {
      var cont = bytes[i + j]
      if ((cont & 0xc0) !== 0x80) return null
      cp = (cp << 6) | (cont & 0x3f)
    }
    out += String.fromCodePoint(cp)
    i += n + 1
  }
  return out
}

function bytesToText(bytes) {
  var text = utf8Decode(bytes)
  if (text !== null) return text
  return bytes.map(function(b) { return String.fromCharCode(b) }).join("")
}

function decodeString(raw) {
  var out = ""
  var bytes = []
  var re = /\\([0-7]{1,3}|x[0-9a-fA-F]{1,2}|.)|[^\\]+/g
  var m
  while ((m = re.exec(raw)) !== null) {
    var e = m[1]
    if (e !== undefined && /^[0-7]+$/.test(e)) { bytes.push(parseInt(e, 8) & 0xff); continue }
    if (e !== undefined && /^x/.test(e)) { bytes.push(parseInt(e.slice(1), 16)); continue }
    if (bytes.length) { out += bytesToText(bytes); bytes = [] }
    if (e === undefined) out += m[0]
    else if (e === "n") out += "\n"
    else if (e === "t") out += "\t"
    else out += e
  }
  if (bytes.length) out += bytesToText(bytes)
  return out
}

// Returns { bySymbol: { symbol: "g a", ... }, count: N }
function parse(text) {
  var bySequence = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = LINE.exec(lines[i])
    if (!m) continue
    var keys = m[1].match(/<([^>]+)>/g).map(function(k) { return k.slice(1, -1) })
    if (keys[0] !== "Multi_key") continue
    keys = keys.slice(1)
    if (keys.length === 0) continue
    var symbol = decodeString(m[2])
    if (!symbol) continue
    bySequence[keys.join(" ")] = symbol
  }
  var bySymbol = {}
  var count = 0
  for (var seq in bySequence) {
    var sym = bySequence[seq]
    var shown = seq.split(" ").map(keyGlyph).join(" ")
    var keyCount = seq.split(" ").length
    count++
    var have = bySymbol[sym]
    if (!have || keyCount < have.length || (keyCount === have.length && shown.length < have.shown.length))
      bySymbol[sym] = { shown: shown, length: keyCount }
  }
  var out = {}
  for (var s in bySymbol) out[s] = bySymbol[s].shown
  return { bySymbol: out, count: count }
}

if (typeof module !== "undefined") module.exports = { parse: parse, keyGlyph: keyGlyph, decodeString: decodeString }
