//
//  SwiftImageMagick.swift
//  SwiftImageMagick
//
//  Created by Assistant on 17/12/2024.
//

import Foundation
import imagemagick

public struct ImageMagick {
    private init() {}
}

struct TextMetrics {
    let width: Double
    let height: Double
    let ascender: Double
    let descender: Double
    let baseline: Double

    // Bounding box coordinates relative to the baseline:
    // x1,y1 (top-left), x2,y2 (bottom-right)
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    var imSize: IMSize {
        IMSize(width: width, height: height)
    }
}

// MARK: - Cross-Platform Geometry Types
public struct IMSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct IMPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = IMPoint(x: 0, y: 0)

}

public struct IMRect: Codable, Hashable, Sendable {
    public var origin: IMPoint
    public var size: IMSize

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = IMPoint(x: x, y: y)
        self.size = IMSize(width: width, height: height)
    }
}

// MARK: - Core Types
extension ImageMagick {
    public struct Image: Sendable {
        private final class WandHolder: @unchecked Sendable {
            let wand: OpaquePointer
            init(wand: OpaquePointer) {
                self.wand = wand
            }
            deinit {
                DestroyMagickWand(wand)
            }
        }

        private let holder: WandHolder

        private init(holder: WandHolder) {
            self.holder = holder
        }

        public init(width: Int, height: Int, background: Color = .white) throws {
            guard let wand = NewMagickWand() else {
                throw Error.initializationFailed
            }

            let status = MagickNewImage(
                wand,
                width.uconstant,
                height.uconstant,
                background.pixelWand
            )

            if status == MagickFalse {
                DestroyMagickWand(wand)
                throw Error.initializationFailed
            }

            self.holder = WandHolder(wand: wand)
        }

        public init(data: Data) throws {
            guard let wand = NewMagickWand() else {
                throw Error.initializationFailed
            }

            let status = data.withUnsafeBytes { ptr -> MagickBooleanType in
                guard let baseAddress = ptr.baseAddress else {
                    return MagickFalse
                }
                return MagickReadImageBlob(wand, baseAddress, ptr.count.uconstant)
            }

            if status == MagickFalse {
                DestroyMagickWand(wand)
                throw Error.invalidImageData
            }

            self.holder = WandHolder(wand: wand)
        }

        public init(contentsOf url: URL) throws {
            guard let wand = NewMagickWand() else {
                throw Error.initializationFailed
            }

            let status = url.path.withCString { cString in
                MagickReadImage(wand, cString)
            }

            if status == MagickFalse {
                DestroyMagickWand(wand)
                throw Error.invalidImageData
            }

            self.holder = WandHolder(wand: wand)
        }

        public func write(to url: URL) throws {
            let status = url.path.withCString { cString in
                MagickWriteImage(holder.wand, cString)
            }

            if status == MagickFalse {
                throw Error.exportFailed
            }
        }

        public func data() throws -> Data {
            var length: Int = 0
            guard let blob = MagickGetImageBlob(holder.wand, &length) else {
                throw Error.exportFailed
            }
            defer { MagickRelinquishMemory(blob) }

            return Data(bytes: blob, count: length)
        }

        public var size: IMSize {
            get throws {
                let width = MagickGetImageWidth(holder.wand)
                let height = MagickGetImageHeight(holder.wand)

                guard width > 0, height > 0 else {
                    throw ImageMagick.Error.invalidImageData
                }

                return IMSize(
                    width: Double(width),
                    height: Double(height)
                )
            }
        }

        public func adding(
            text configuration: ImageMagick.TextConfiguration
        ) throws -> ImageMagick.Image {
            guard let newWand = CloneMagickWand(holder.wand) else {
                throw ImageMagick.Error.drawingFailed
            }

            guard let drawingWand = NewDrawingWand() else {
                DestroyMagickWand(newWand)
                throw ImageMagick.Error.drawingFailed
            }

            let imageSize = try size
            let (x, y, finalAlignment) = try configuration.calculatePositionAndAlignment(in: imageSize)

            try configuration.configure(drawingWand: drawingWand, alignment: finalAlignment)

            DrawAnnotation(
                drawingWand,
                Double(x),
                Double(y),
                configuration.text
            )

            let status = MagickDrawImage(newWand, drawingWand)
            DestroyDrawingWand(drawingWand)

            if status == MagickFalse {
                DestroyMagickWand(newWand)
                throw ImageMagick.Error.textRenderingFailed("!status == MagickFalse")
            }

            return ImageMagick.Image(holder: WandHolder(wand: newWand))
        }

        public func resizing(
            to newSize: IMSize,
            maintaining aspectRatio: Bool = true
        ) throws -> ImageMagick.Image {
            guard let newWand = CloneMagickWand(holder.wand) else {
                throw ImageMagick.Error.resizeFailed
            }

            let currentSize = try size
            var finalWidth = newSize.width
            var finalHeight = newSize.height

            if aspectRatio {
                let currentRatio = currentSize.width / currentSize.height
                let newRatio = newSize.width / newSize.height

                if currentRatio > newRatio {
                    finalHeight = newSize.width / currentRatio
                } else {
                    finalWidth = newSize.height * currentRatio
                }
            }

            let status = MagickResizeImage(
                newWand,
                size_t(finalWidth),
                size_t(finalHeight),
                LanczosFilter
            )

            if status == MagickFalse {
                DestroyMagickWand(newWand)
                throw ImageMagick.Error.resizeFailed
            }

            return ImageMagick.Image(holder: WandHolder(wand: newWand))
        }

        public func cropping(
            to rect: IMRect
        ) throws -> ImageMagick.Image {
            guard let newWand = CloneMagickWand(holder.wand) else {
                throw ImageMagick.Error.cropFailed
            }

            let currentSize = try size

            let x = Swift.max(0, rect.origin.x)
            let y = Swift.max(0, rect.origin.y)
            let width = Swift.min(rect.size.width, currentSize.width - rect.origin.x)
            let height = Swift.min(rect.size.height, currentSize.height - rect.origin.y)

            let safeRect = IMRect(
                x: x,
                y: y,
                width: width,
                height: height
            )

            let status = MagickCropImage(
                newWand,
                size_t(safeRect.size.width),
                size_t(safeRect.size.height),
                Int(safeRect.origin.x),
                Int(safeRect.origin.y)
            )

            if status == MagickFalse {
                DestroyMagickWand(newWand)
                throw ImageMagick.Error.cropFailed
            }

            _ = MagickResetImagePage(newWand, nil)

            return ImageMagick.Image(holder: WandHolder(wand: newWand))
        }
    }
}

// MARK: - Extensions for Type Conversion
private extension Int {
    var uconstant: size_t {
        size_t(self)
    }
}

// MARK: - Color Extension for PixelWand Conversion
private extension ImageMagick.Color {
    var pixelWand: OpaquePointer? {
        let wand = NewPixelWand()
        PixelSetRed(wand, red)
        PixelSetGreen(wand, green)
        PixelSetBlue(wand, blue)
        PixelSetAlpha(wand, alpha)
        return wand
    }
}

// MARK: - Color Type
extension ImageMagick {
    public struct Color: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
            self.alpha = min(max(alpha, 0), 1)
        }

        public static let black = Color(red: 0, green: 0, blue: 0)
        public static let white = Color(red: 1, green: 1, blue: 1)
        public static let red = Color(red: 1, green: 0, blue: 0)
        public static let green = Color(red: 0, green: 1, blue: 0)
        public static let blue = Color(red: 0, green: 0, blue: 1)
        public static let yellow = Color(red: 1, green: 1, blue: 0)
        public static let cyan = Color(red: 0, green: 1, blue: 1)
        public static let magenta = Color(red: 1, green: 0, blue: 1)
        public static let gray = Color(red: 0.5, green: 0.5, blue: 0.5)
        public static let transparent = Color(red: 0, green: 0, blue: 0, alpha: 0)

        public static func rgb(_ red: Int, _ green: Int, _ blue: Int, alpha: Double = 1.0) -> Color {
            Color(
                red: Double(min(max(red, 0), 255)) / 255.0,
                green: Double(min(max(green, 0), 255)) / 255.0,
                blue: Double(min(max(blue, 0), 255)) / 255.0,
                alpha: alpha
            )
        }

        public static func hex(_ string: String) -> Color? {
            var hex = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if hex.hasPrefix("#") {
                hex = String(hex.dropFirst())
            }

            guard hex.count == 6 else { return nil }

            var rgbValue: UInt64 = 0
            guard Scanner(string: hex).scanHexInt64(&rgbValue) else { return nil }

            return rgb(
                Int((rgbValue & 0xFF0000) >> 16),
                Int((rgbValue & 0x00FF00) >> 8),
                Int(rgbValue & 0x0000FF)
            )
        }

        public static func gray(_ value: Double, alpha: Double = 1.0) -> Color {
            let val = min(max(value, 0), 1)
            return Color(red: val, green: val, blue: val, alpha: alpha)
        }
    }
}

// MARK: - Additional Color Operations
extension ImageMagick.Color {
    public func withAlpha(_ newAlpha: Double) -> ImageMagick.Color {
        ImageMagick.Color(red: red, green: green, blue: blue, alpha: newAlpha)
    }

    public func adjustingBrightness(by factor: Double) -> ImageMagick.Color {
        let factor = min(max(factor, -1), 1)
        if factor > 0 {
            return ImageMagick.Color(
                red: red + (1 - red) * factor,
                green: green + (1 - green) * factor,
                blue: blue + (1 - blue) * factor,
                alpha: alpha
            )
        } else {
            return ImageMagick.Color(
                red: red * (1 + factor),
                green: green * (1 + factor),
                blue: blue * (1 + factor),
                alpha: alpha
            )
        }
    }

    public var inverted: ImageMagick.Color {
        ImageMagick.Color(
            red: 1 - red,
            green: 1 - green,
            blue: 1 - blue,
            alpha: alpha
        )
    }
}

// MARK: - String Representation
extension ImageMagick.Color {
    public var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}

// MARK: - Equatable and Hashable Implementation
extension ImageMagick.Color {
    public static func == (lhs: ImageMagick.Color, rhs: ImageMagick.Color) -> Bool {
        abs(lhs.red - rhs.red) < 0.001 &&
        abs(lhs.green - rhs.green) < 0.001 &&
        abs(lhs.blue - rhs.blue) < 0.001 &&
        abs(lhs.alpha - rhs.alpha) < 0.001
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(red)
        hasher.combine(green)
        hasher.combine(blue)
        hasher.combine(alpha)
    }
}

// MARK: - Text Configuration
extension ImageMagick {
    public struct TextConfiguration: Sendable {

        public struct Style: Sendable {
            public let fontName: String
            public let fontSize: Double
            public let color: Color
            public let alignment: Alignment

            public init(
                fontName: String = "Helvetica",
                fontSize: Double = 24,
                color: Color = .black,
                alignment: Alignment = .center
            ) {
                self.fontName = fontName
                self.fontSize = fontSize
                self.color = color
                self.alignment = alignment
            }

            internal func metrics(for text: String) throws -> TextMetrics {
                guard let fontWand = NewMagickWand() else {
                    throw ImageMagick.Error.textRenderingFailed("No fontWand")
                }
                defer { DestroyMagickWand(fontWand) }

                let status = MagickNewImage(fontWand, 1, 1, NewPixelWand())
                guard status == MagickTrue else {
                    throw ImageMagick.Error.textRenderingFailed("Could not create temp image for metrics")
                }

                let drawingWand = NewDrawingWand()
                defer { DestroyDrawingWand(drawingWand) }

                DrawSetFont(drawingWand, fontName)
                DrawSetFontSize(drawingWand, fontSize)

                guard let metricsPtr = MagickQueryFontMetrics(fontWand, drawingWand, text) else {
                    throw ImageMagick.Error.textRenderingFailed("No metrics returned")
                }
                defer { MagickRelinquishMemory(metricsPtr) }

                // According to ImageMagick docs for MagickQueryFontMetrics:
                // metricsPtr:
                // 0: character width
                // 1: character height
                // 2: ascender
                // 3: descender
                // 4: text width
                // 5: text height
                // 6: max horizontal advance
                // 7: baseline
                // 8: x1
                // 9: y1
                // 10: x2
                // 11: y2

                return TextMetrics(
                    width: metricsPtr[4],
                    height: metricsPtr[5],
                    ascender: metricsPtr[2],
                    descender: metricsPtr[3],
                    baseline: metricsPtr[7],
                    x1: metricsPtr[8],
                    y1: metricsPtr[9],
                    x2: metricsPtr[10],
                    y2: metricsPtr[11]
                )
            }
        }

        public enum Alignment: Sendable {
            case left
            case center
            case right

            internal var alignType: AlignType {
                switch self {
                case .left: return LeftAlign
                case .center: return CenterAlign
                case .right: return RightAlign
                }
            }
        }

        public enum Position: Sendable {
            // Centered positions
            case center(offset: IMPoint = .zero)
            case centerHorizontally(y: Double, xOffset: Double = 0)
            case centerVertically(x: Double, yOffset: Double = 0)

            // Edge positions
            case top(offset: Double = 0)
            case bottom(offset: Double = 0)
            case left(offset: Double = 0)
            case right(offset: Double = 0)

            // Corner positions
            case topLeft(offset: IMPoint = .zero)
            case topRight(offset: IMPoint = .zero)
            case bottomLeft(offset: IMPoint = .zero)
            case bottomRight(offset: IMPoint = .zero)

            // Middle edge positions
            case middleLeft(offset: Double = 0)
            case middleRight(offset: Double = 0)

            // Custom position
            case custom(x: Double, y: Double)
        }

        public let text: String
        public let position: Position
        public let style: Style

        public init(
            text: String,
            position: Position = .center(),
            style: Style = Style()
        ) {
            self.text = text
            self.position = position
            self.style = style
        }

        internal func calculatePositionAndAlignment(in imageSize: IMSize) throws -> (x: Int, y: Int, Alignment) {
            let metrics = try style.metrics(for: text)

            // Determine final alignment based on position
            let finalAlignment: Alignment
            switch position {
            case .topLeft, .left, .bottomLeft, .middleLeft:
                finalAlignment = .left
            case .topRight, .right, .bottomRight, .middleRight:
                finalAlignment = .right
            case .center, .centerHorizontally, .centerVertically, .top, .bottom:
                finalAlignment = .center
            case .custom:
                // Keep user-defined alignment in custom mode
                finalAlignment = style.alignment
            }

            // Create a temporary style with finalAlignment for correct positioning
            let modifiedStyle = Style(
                fontName: style.fontName,
                fontSize: style.fontSize,
                color: style.color,
                alignment: finalAlignment
            )

            let point = position.resolvePosition(
                for: imageSize,
                textSize: metrics.imSize,
                style: modifiedStyle,
                metrics: metrics
            )
            return (Int(point.x), Int(point.y), finalAlignment)
        }

        internal func configure(drawingWand: OpaquePointer, alignment: Alignment) throws {
            DrawSetFont(drawingWand, style.fontName)
            DrawSetFontSize(drawingWand, style.fontSize)

            let pixelWand = NewPixelWand()
            defer { DestroyPixelWand(pixelWand) }

            PixelSetRed(pixelWand, style.color.red)
            PixelSetGreen(pixelWand, style.color.green)
            PixelSetBlue(pixelWand, style.color.blue)
            PixelSetAlpha(pixelWand, style.color.alpha)

            DrawSetFillColor(drawingWand, pixelWand)
            DrawSetTextAlignment(drawingWand, alignment.alignType)
        }
    }
}

extension ImageMagick.TextConfiguration.Position {
    fileprivate func resolvePosition(
        for imageSize: IMSize,
        textSize: IMSize,
        style: ImageMagick.TextConfiguration.Style,
        metrics: TextMetrics
    ) -> IMPoint {

        func baselineForTop(yOffset: Double) -> Double {
            return yOffset - metrics.y1
        }

        func baselineForBottom(yOffset: Double) -> Double {
            return (imageSize.height - yOffset) - metrics.y2
        }

        func baselineForVerticalCenter(yOffset: Double = 0) -> Double {
            // Visually pleasing vertical centering:
            // baseline = center + offset + ascender - half(text height)
            return imageSize.height / 2 + yOffset + metrics.ascender - (metrics.height / 2)
        }

        func horizontalCenter(xOffset: Double = 0) -> Double {
            return imageSize.width / 2 + xOffset
        }

        func xPositionForLeft(xOffset: Double) -> Double {
            return xOffset
        }

        func xPositionForRight(xOffset: Double) -> Double {
            return imageSize.width - xOffset
        }

        switch self {
        case .center(let offset):
            return IMPoint(
                x: horizontalCenter(xOffset: offset.x),
                y: baselineForVerticalCenter(yOffset: offset.y)
            )

        case .centerHorizontally(let y, let xOffset):
            return IMPoint(
                x: horizontalCenter(xOffset: xOffset),
                y: y
            )

        case .centerVertically(let x, let yOffset):
            return IMPoint(
                x: x,
                y: baselineForVerticalCenter(yOffset: yOffset)
            )

        case .top(let offset):
            return IMPoint(
                x: horizontalCenter(),
                y: baselineForTop(yOffset: offset)
            )

        case .bottom(let offset):
            return IMPoint(
                x: horizontalCenter(),
                y: baselineForBottom(yOffset: offset)
            )

        case .left(let offset):
            return IMPoint(
                x: xPositionForLeft(xOffset: offset),
                y: baselineForVerticalCenter()
            )

        case .right(let offset):
            return IMPoint(
                x: xPositionForRight(xOffset: offset),
                y: baselineForVerticalCenter()
            )

        case .topLeft(let offset):
            return IMPoint(
                x: xPositionForLeft(xOffset: offset.x),
                y: baselineForTop(yOffset: offset.y)
            )

        case .topRight(let offset):
            return IMPoint(
                x: xPositionForRight(xOffset: offset.x),
                y: baselineForTop(yOffset: offset.y)
            )

        case .bottomLeft(let offset):
            return IMPoint(
                x: xPositionForLeft(xOffset: offset.x),
                y: baselineForBottom(yOffset: offset.y)
            )

        case .bottomRight(let offset):
            return IMPoint(
                x: xPositionForRight(xOffset: offset.x),
                y: baselineForBottom(yOffset: offset.y)
            )

        case .middleLeft(let offset):
            return IMPoint(
                x: xPositionForLeft(xOffset: offset),
                y: baselineForVerticalCenter()
            )

        case .middleRight(let offset):
            return IMPoint(
                x: xPositionForRight(xOffset: offset),
                y: baselineForVerticalCenter()
            )

        case .custom(let x, let y):
            return IMPoint(x: x, y: y)
        }
    }
}

// MARK: - Error Handling
extension ImageMagick {
    public enum Error: Swift.Error {
        case initializationFailed
        case invalidImageData
        case drawingFailed
        case exportFailed
        case resizeFailed
        case cropFailed
        case textRenderingFailed(String)
    }
}

extension ImageMagick {
    public actor ResourceManager {
        public static let shared = ResourceManager()

        private var isInitialized = false

        private init() {}

        public func initialize() throws {
            guard !isInitialized else { return }

            MagickWandGenesis()

            _ = MagickSetResourceLimit(AreaResource, 64 * 1024 * 1024)
            _ = MagickSetResourceLimit(MemoryResource, 256 * 1024 * 1024)
            _ = MagickSetResourceLimit(ThreadResource, 2)

            isInitialized = true
        }

        public func terminate() {
            guard isInitialized else { return }
            MagickWandTerminus()
            isInitialized = false
        }

        public var initialized: Bool {
            isInitialized
        }

        deinit {
            if isInitialized {
                MagickWandTerminus()
            }
        }
    }
}

extension ImageMagick.ResourceManager {
    public func withImageMagick<T>(_ block: () throws -> T) async throws -> T {
        try await initialize()
        defer { Task { await terminate() } }
        return try block()
    }
}
