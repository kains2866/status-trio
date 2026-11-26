import AppKit
import CryptoKit
import Foundation
@testable import StatusTrioCore

@MainActor
func matchesStaticSymbolRaster(_ pixels: PixelBuffer, fingerprint: String) -> Bool? {
    guard let symbol = staticFingerprintSymbol() else { return nil }
    let size = symbol.size
    switch (ProcessInfo.processInfo.operatingSystemVersion.majorVersion, size.width, size.height) {
    case (26, _, _):
        return fingerprint == "9dcba3184f0953f8c173cc2f846977f01b84510a8505166bd6a8048f44d8fd97"
    case (27, 50, 47):
        guard pixels.width == 40, pixels.height == 40 else { return false }
        let reference = staticSymbolRaster(symbol).bytes
        var outerPixels = pixels.bytes
        for row in 11..<29 {
            let center = (row * 40 + 11) * 4..<(row * 40 + 29) * 4
            guard pixels.bytes[center].elementsEqual(reference[center]) else { return false }
            outerPixels.replaceSubrange(center, with: repeatElement(0, count: center.count))
        }
        return rasterFingerprint(Data(outerPixels))
            == "03159ca152599ae8e4664fbd434d73a1327f4f8584f4e21f45db32d433d00ef7"
    case (27, 51, 46):
        // CI's 1x display rasterises the same symbol metrics differently from
        // the local Retina variant; keep each exact environment pair bounded.
        return [
            "377721331486253656c666fdc02ca98650f5d4421d623a54f388fd8389da339e",
            "c11034a3fd7363b1539936aaa5135d03acab67545a13800b56ccf432946971af"
        ].contains(fingerprint)
    default:
        return nil
    }
}

@MainActor
private func staticFingerprintSymbol() -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: 38, weight: .semibold)
        .applying(.init(hierarchicalColor: NSColor(cgColor: CGColor(gray: 1, alpha: 1))!))
    return NSImage(
        systemSymbolName: "wifi.slash", variableValue: 1, accessibilityDescription: nil
    )?.withSymbolConfiguration(config)
}

@MainActor
func printStaticSymbolRasterDiagnostics() {
    for (label, cacheMode) in [("default", NSImage.CacheMode.default), ("never", .never)] {
        guard let image = staticFingerprintSymbol() else { continue }
        image.cacheMode = cacheMode
        let raster = staticSymbolRaster(image)
        print(
            "SYMBOL_RASTER_DIAGNOSTIC mode=\(label) size=\(image.size) offset=\(raster.offset)"
                + " measureBounds=\(raster.bounds)"
                + " pixels=40x40 sha256=\(rasterFingerprint(raster.bytes)) rgbaBase64=\(raster.bytes.base64EncodedString())"
        )
    }
}

@MainActor
private func staticSymbolRaster(_ image: NSImage) -> (bytes: Data, offset: CGFloat, bounds: [Int]) {
    let size = image.size
    let measure = CGContext(
        data: nil, width: Int(ceil(size.width * 6)), height: Int(ceil(size.height * 6)),
        bitsPerComponent: 8, bytesPerRow: Int(ceil(size.width * 6)) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    measure.scaleBy(x: 6, y: 6)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: measure, flipped: false)
    image.draw(in: CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = measure.data!.assumingMemoryBound(to: UInt8.self)
    var minX = measure.width
    var maxX = -1
    var minY = measure.height
    var maxY = -1
    for row in 0..<measure.height {
        for column in 0..<measure.width where data[row * measure.bytesPerRow + column * 4 + 3] > 0 {
            minX = min(minX, column)
            maxX = max(maxX, column)
            minY = min(minY, row)
            maxY = max(maxY, row)
        }
    }
    let offset = CGFloat(minX + maxX + 1) / 12 - size.width / 2
    let context = CGContext(
        data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: 0, y: 40)
    context.scaleBy(x: 1.0 / 3, y: -1.0 / 3)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.scaleBy(x: 1, y: -1)
    image.draw(in: CGRect(
        x: 59.5 - size.width / 2 - offset,
        y: -(61.48715261785473 + size.height / 2),
        width: size.width, height: size.height
    ))
    NSGraphicsContext.restoreGraphicsState()
    return (Data(bytes: context.data!, count: 6_400), offset, [minX, minY, maxX, maxY])
}

func rasterFingerprint(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
