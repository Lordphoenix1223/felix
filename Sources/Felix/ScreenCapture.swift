import AppKit
import ImageIO

enum ScreenCapture {
    static func fullScreenJPEG(on screen: NSScreen) -> Data? {
        jpeg(for: screen.frame, on: screen)
    }

    static func jpeg(for selection: NSRect, on screen: NSScreen) -> Data? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let full = CGDisplayCreateImage(displayID) else { return nil }

        let scale = screen.backingScaleFactor
        let localX = max(0, selection.origin.x - screen.frame.origin.x)
        let localY = max(0, selection.origin.y - screen.frame.origin.y)
        let pixelRect = CGRect(
            x: localX * scale,
            y: (screen.frame.height - localY - selection.height) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))

        guard pixelRect.width > 2, pixelRect.height > 2, let cropped = full.cropping(to: pixelRect) else { return nil }
        let tiff = NSBitmapImageRep(cgImage: cropped).tiffRepresentation
        let source = tiff.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        let thumbnail = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1800,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) } ?? cropped
        let bitmap = NSBitmapImageRep(cgImage: thumbnail)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
