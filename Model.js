.pragma library

// Pure helpers for Panel.qml. Kept out of the QML so they can be reasoned
// about (and, where it matters, corrected) without touching layout.

var SLOTS = ["bg", "accent", "bright_fg", "fg", "green", "yellow", "red"]

var PURPOSE = {
  bg: "background",
  accent: "titles, seek bar",
  bright_fg: "primary text",
  fg: "muted text",
  green: "playing, spectrum low",
  yellow: "warnings, spectrum mid",
  red: "errors, spectrum top"
}

function slotPurpose(slot) {
  return PURPOSE[slot] || ""
}

// The helper always prints one JSON object, but a crashed interpreter or a
// stray warning on stdout would not. Treat anything unparseable as an error
// rather than letting an exception escape into a signal handler, where it
// would leave the panel stuck showing "Loading...".
function parseResult(text) {
  var raw = String(text || "").trim()
  if (!raw.length) return { error: "the skin helper returned nothing" }
  try {
    var parsed = JSON.parse(raw)
    return (parsed && typeof parsed === "object") ? parsed : { error: "unexpected helper output" }
  } catch (e) {
    return { error: "could not read helper output: " + raw.slice(0, 120) }
  }
}

function isHex(value) {
  return /^#?[0-9a-fA-F]{6}$/.test(String(value || "").trim())
}

// Returns a new palette with one slot replaced, or null if the value is not a
// color. Copying rather than mutating is what makes QML notice the change:
// assigning into an existing object does not re-evaluate the bindings that
// read it.
function withSlot(palette, slot, value) {
  if (SLOTS.indexOf(slot) === -1 || !isHex(value)) return null
  var text = String(value).trim().toLowerCase()
  if (text.charAt(0) !== "#") text = "#" + text
  var next = {}
  for (var key in palette) next[key] = palette[key]
  next[slot] = text
  return next
}

// One line describing what the converter had to do, so a skin that needed
// heavy correction says so instead of quietly looking wrong.
function repairSummary(data) {
  var name = data.name || data.theme || "skin"
  var invented = (data.invented || []).length
  var adjusted = (data.adjusted || []).length
  if (!invented && !adjusted) return name + " converted cleanly"
  var parts = []
  if (adjusted) parts.push(adjusted + " adjusted for contrast")
  if (invented) parts.push(invented + " missing from the skin")
  return name + " — " + parts.join(", ")
}

function wrap(index, length) {
  if (length <= 0) return 0
  return ((index % length) + length) % length
}

// Nudge a hex color lighter (positive) or darker (negative) by mixing toward
// white or black in sRGB. Crude next to the Python engine's OKLab math, but
// for ±8% interactive nudges the difference is imperceptible and it keeps
// the panel synchronous.
function nudge(hex, amount) {
  if (!isHex(hex)) return hex
  var h = String(hex).replace("#", "")
  var target = amount > 0 ? 255 : 0
  var t = Math.min(1, Math.abs(amount))
  var out = "#"
  for (var i = 0; i < 3; i++) {
    var c = parseInt(h.substr(i * 2, 2), 16)
    c = Math.round(c + (target - c) * t)
    out += (c < 16 ? "0" : "") + c.toString(16)
  }
  return out
}
