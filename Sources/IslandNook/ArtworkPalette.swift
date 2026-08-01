import SwiftUI
import AppKit

enum ArtworkPalette {
    static let fallback: [Color] = [.pink, .purple, .cyan, .green]

    static func extract(from image: NSImage) -> [Color] {
        let side = 28
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return fallback }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var candidates: [(color: NSColor, score: CGFloat)] = []
        for y in stride(from: 1, to: side, by: 2) {
            for x in stride(from: 1, to: side, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.7 else { continue }
                let saturation = color.saturationComponent
                let brightness = color.brightnessComponent
                guard brightness > 0.12, brightness < 0.97, saturation > 0.16 else { continue }
                candidates.append((color, saturation * (0.55 + brightness * 0.45)))
            }
        }
        candidates.sort { $0.score > $1.score }

        var selected: [NSColor] = []
        for candidate in candidates {
            let isDistinct = selected.allSatisfy { existing in
                let red = candidate.color.redComponent - existing.redComponent
                let green = candidate.color.greenComponent - existing.greenComponent
                let blue = candidate.color.blueComponent - existing.blueComponent
                return sqrt(red * red + green * green + blue * blue) > 0.24
            }
            if isDistinct { selected.append(candidate.color) }
            if selected.count == 4 { break }
        }
        guard !selected.isEmpty else { return fallback }
        while selected.count < 4 {
            let base = selected[selected.count % selected.count]
            selected.append(base.blended(withFraction: 0.28, of: .white) ?? base)
        }
        return selected.map(Color.init(nsColor:))
    }
}
