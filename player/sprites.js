.pragma library

// Winamp 2.x main-window geometry.
//
// These offsets are not ours to choose: every skin ever made was cut against
// them, so a wrong number here shows up as a sliced button on all 102,000
// skins at once. They match the classic skinning spec (the same table Webamp
// renders from). Coordinates are unscaled skin pixels; the window multiplies
// by an integer zoom.
//
// Sheets are addressed as [x, y, w, h] rectangles into their bitmap.

var MAIN_WIDTH = 275
var MAIN_HEIGHT = 116

// ---- Transport ----------------------------------------------------------
// cbuttons.bmp is 136x36: released states on the top row, pressed directly
// beneath. Eject is the odd one out at 16px tall, so its pressed state sits
// 16px down rather than 18.
var BUTTONS = [
  { id: "previous", sheet: "cbuttons", rect: [  0, 0, 23, 18], press: [  0, 18, 23, 18], at: [ 16, 88] },
  { id: "play",     sheet: "cbuttons", rect: [ 23, 0, 23, 18], press: [ 23, 18, 23, 18], at: [ 39, 88] },
  { id: "pause",    sheet: "cbuttons", rect: [ 46, 0, 23, 18], press: [ 46, 18, 23, 18], at: [ 62, 88] },
  { id: "stop",     sheet: "cbuttons", rect: [ 69, 0, 23, 18], press: [ 69, 18, 23, 18], at: [ 85, 88] },
  { id: "next",     sheet: "cbuttons", rect: [ 92, 0, 22, 18], press: [ 92, 18, 22, 18], at: [108, 88] },
  { id: "eject",    sheet: "cbuttons", rect: [114, 0, 22, 16], press: [114, 16, 22, 16], at: [136, 89] }
]

// ---- Title bar ----------------------------------------------------------
var TITLEBAR = {
  active:   [27,  0, 275, 14],
  inactive: [27, 15, 275, 14],
  at: [0, 0]
}

var WINDOW_BUTTONS = [
  { id: "shade",    rect: [ 0, 0, 9, 9], press: [ 0, 9, 9, 9], at: [254, 3] },
  { id: "close",    rect: [18, 0, 9, 9], press: [18, 9, 9, 9], at: [264, 3] }
]

// ---- Time readout -------------------------------------------------------
// numbers.bmp packs 11 glyphs of 9x13 (digits then a blank). Skins that ship
// nums_ex.bmp instead add a leading minus, shifting every digit by one cell --
// 15.7% of the corpus, so this is a real code path, not an edge case.
var DIGIT = { w: 9, h: 13 }
var DIGIT_AT = [[48, 26], [60, 26], [78, 26], [90, 26]]  // mm:ss, colon is painted in main.bmp
var MINUS_AT = [36, 26]

function digitRect(value, extended) {
  // nums_ex.bmp leads with the minus sign, so digit N lives one cell further in.
  var index = extended ? value + 1 : value
  return [index * DIGIT.w, 0, DIGIT.w, DIGIT.h]
}

// ---- Bitmap font --------------------------------------------------------
// text.bmp is 155x18: three rows of 31 glyphs, each 5x6. Only the cells the
// spec assigns are listed; the trailing cells of each row are unspecified and
// skins fill them arbitrarily, so they are never addressed.
var CHAR = { w: 5, h: 6, perRow: 31 }
var CHAR_ROWS = [
  "abcdefghijklmnopqrstuvwxyz\"@",
  "0123456789….:()-'!_+\\/[]^&%.=$#",
  "åöä?* "
]
var TITLE_AT = [111, 27]
var TITLE_CELLS = 30   // how many glyphs fit in the marquee

// Returns null for anything the sheet has no cell for, including spaces.
// There is no dependable blank cell to fall back on: the trailing cells of
// each row are unused by the spec, and skins fill them with whatever they
// like -- the Matrix skin puts a decorative glyph there, so borrowing one as
// a "space" printed arrowheads between words. Callers leave a gap instead.
function charRect(ch) {
  var lower = String(ch).toLowerCase()
  for (var row = 0; row < CHAR_ROWS.length; row++) {
    var col = CHAR_ROWS[row].indexOf(lower)
    if (col !== -1) return [col * CHAR.w, row * CHAR.h, CHAR.w, CHAR.h]
  }
  return null
}

// ---- Sliders ------------------------------------------------------------
var POSBAR = {
  background: [0, 0, 248, 10],
  thumb:      [248, 0, 29, 10],
  thumbDown:  [278, 0, 29, 10],
  at: [16, 72],
  travel: 219            // background width minus thumb width
}

// volume.bmp stacks 28 background frames of 68x13, one per loudness step, so
// the bar itself brightens as it fills.
var VOLUME = {
  frames: 28,
  frameHeight: 15,
  size: [68, 13],
  thumb:     [15, 422, 14, 11],
  thumbDown: [ 0, 422, 14, 11],
  at: [107, 57],
  travel: 51
}

function volumeFrameRect(fraction) {
  var i = Math.max(0, Math.min(VOLUME.frames - 1, Math.round(fraction * (VOLUME.frames - 1))))
  return [0, i * VOLUME.frameHeight, VOLUME.size[0], VOLUME.size[1]]
}

// ---- Indicators ---------------------------------------------------------
var PLAY_STATE = {
  playing: [ 0, 0, 9, 9],
  paused:  [ 9, 0, 9, 9],
  stopped: [18, 0, 9, 9],
  at: [24, 28]
}

var MONOSTER = {
  monoOn:    [ 0,  0, 29, 12],
  monoOff:   [ 0, 12, 29, 12],
  stereoOn:  [29,  0, 29, 12],
  stereoOff: [29, 12, 29, 12],
  monoAt:   [212, 41],
  stereoAt: [239, 41]
}

// ---- Toggles ------------------------------------------------------------
var SHUFREP = {
  repeatOff:      [ 0,  0, 28, 15],
  repeatOn:       [ 0, 30, 28, 15],
  shuffleOff:     [28,  0, 47, 15],
  shuffleOn:      [28, 30, 47, 15],
  eqOff:          [ 0, 61, 23, 12],
  eqOn:           [ 0, 73, 23, 12],
  playlistOff:    [23, 61, 23, 12],
  playlistOn:     [23, 73, 23, 12],
  shuffleAt:  [164, 89],
  repeatAt:   [210, 89],
  eqAt:       [219, 58],
  playlistAt: [242, 58]
}

// ---- Visualizer ---------------------------------------------------------
// The analyzer draws into a fixed well in main.bmp; the background shows
// through, so nothing is blitted here -- bars are drawn directly.
var VIS = { at: [24, 43], size: [76, 16] }

// ---- Helpers ------------------------------------------------------------

function formatClock(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var m = Math.floor(total / 60)
  var s = total % 60
  // Winamp shows minutes past 99 by simply overflowing the two cells.
  return [Math.floor(m / 10) % 10, m % 10, Math.floor(s / 10), s % 10]
}

// ---- Visualizer colours -------------------------------------------------

// viscolor.txt is 24 "r,g,b" lines with optional `// comment` tails. Indices
// 0-1 are the analyzer's own background, 2-17 the spectrum ramp from the top
// of a bar down to its base, 18-22 the oscilloscope, 23 the peak dot.
// Returns the 16 ramp entries top-first, or [] if the file is unusable --
// callers fall back to a flat colour rather than drawing nothing.
function parseViscolor(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})/.exec(lines[i].split("//")[0])
    if (m) out.push(Qt.rgba(Math.min(255, +m[1]) / 255, Math.min(255, +m[2]) / 255, Math.min(255, +m[3]) / 255, 1))
  }
  return out.length >= 18 ? out.slice(2, 18) : []
}

// One NDJSON frame from `cliamp visstream`: {"bands":[0..1, ...]}.
// Bad frames yield null so the last good one keeps showing rather than the
// analyzer flickering to empty.
function parseBands(line) {
  try {
    var frame = JSON.parse(String(line))
    return (frame && frame.bands && frame.bands.length) ? frame.bands : null
  } catch (e) {
    return null
  }
}

// The analyzer well is 76x16; Winamp draws bars 3px wide with a 1px gutter.
var VIS_BAR_WIDTH = 3
var VIS_BAR_GAP = 1
var VIS_ROWS = 16

function visBarCount() {
  return Math.floor((VIS.size[0] + VIS_BAR_GAP) / (VIS_BAR_WIDTH + VIS_BAR_GAP))
}

// Resample however many bands the player emits onto the bars we can draw.
function resample(bands, count) {
  if (!bands || !bands.length) return []
  var out = []
  for (var i = 0; i < count; i++) {
    var pos = (i / Math.max(1, count - 1)) * (bands.length - 1)
    var lo = Math.floor(pos), hi = Math.min(bands.length - 1, lo + 1)
    var t = pos - lo
    out.push(bands[lo] * (1 - t) + bands[hi] * t)
  }
  return out
}
