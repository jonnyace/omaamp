import QtQuick

// One rectangle cut out of a Winamp sprite sheet.
//
// Named SkinSprite because QtQuick already exports a `Sprite` (the
// SpriteSequence frame descriptor, which is not an Item) -- a local Sprite.qml
// loses to it, and the failure reads as "Image has no property y".
//
// Every visible piece of the player is one of these. Skins are pixel art cut
// to exact cell boundaries, so this deliberately never filters: `smooth` and
// `mipmap` stay off and the size is always an integer multiple of the source
// rect, otherwise edges bleed into neighbouring sprites on the sheet.
Image {
  id: root

  // Directory holding the normalised sheets, and which sheet to cut from.
  property string dir: ""
  property string sheet: ""
  // [x, y, w, h] in unscaled skin pixels.
  property var rect: [0, 0, 0, 0]
  property int zoom: 2

  readonly property int cellWidth: rect && rect.length === 4 ? rect[2] : 0
  readonly property int cellHeight: rect && rect.length === 4 ? rect[3] : 0

  source: (dir && sheet) ? "file://" + dir + "/" + sheet : ""
  sourceClipRect: rect && rect.length === 4
    ? Qt.rect(rect[0], rect[1], rect[2], rect[3])
    : Qt.rect(0, 0, 0, 0)

  width: cellWidth * zoom
  height: cellHeight * zoom

  smooth: false
  mipmap: false
  // Sheets are small and read from a local cache; loading them synchronously
  // avoids a frame where half the window is missing.
  asynchronous: false
  // A skin missing an optional sheet should leave a hole, not an error icon.
  visible: status === Image.Ready
}
