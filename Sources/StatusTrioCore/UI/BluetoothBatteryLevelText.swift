import AppKit
import SwiftUI

/// Draws a device's level pieces as one run of text.
///
/// A `Text` and a `Text(Image(systemName:))` concatenate into a single `Text`, so
/// a row keeps one line, one font and one truncation behaviour while one piece
/// of it is a glyph. Both surfaces that show a level — the device rows and the
/// popover's summary line — go through here, so the charging case cannot be a
/// glyph on one and a word on the other.
enum BluetoothBatteryLevelText {
    /// The pieces as one drawable run, in the order they were built.
    static func drawn(
        _ segments: [BluetoothBatterySegment],
        symbolImage: (String) -> NSImage? = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    ) -> Text {
        segments.reduce(Text(verbatim: "")) { run, segment in
            switch segment {
            case .text(let value):
                return run + Text(verbatim: value)
            case .charging:
                guard symbolImage("bolt.fill") != nil else { return run }
                return run + Text(verbatim: " ") + Text(Image(systemName: "bolt.fill"))
            case .symbol(let name, let label):
                // A symbol Apple drops in a later release must not take the
                // meaning with it: the label stands in for the glyph, the way
                // the row's other icon lookups fall back rather than draw blank.
                guard symbolImage(name) != nil else {
                    return run + Text(verbatim: label)
                }
                return run + Text(Image(systemName: name))
            }
        }
    }
}
