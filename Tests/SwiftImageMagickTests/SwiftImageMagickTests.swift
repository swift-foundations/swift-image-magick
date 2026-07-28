import Foundation
import SwiftImageMagick
import Testing

@Suite("ImageMagick Text Tests")
struct ImageMagickTextTests {

    @Test("Draw Centered Text on Image")
    func center() async throws {
        try await ImageMagick.ResourceManager.shared.withImageMagick {
            // Create a 500x500 image with a red background
            var image = try ImageMagick.Image(width: 500, height: 500, background: .red)

            // Define text style and configuration
            let style = ImageMagick.TextConfiguration.Style(
                fontName: "Helvetica",
                fontSize: 72,
                color: .white,
                alignment: .center
            )

            // Position text in the center
            let textConfig = ImageMagick.TextConfiguration(
                text: "coenttb",
                position: .center(),
                style: style
            )

            // Render the text on the image
            image = try image.adding(text: textConfig)

            // Save the resulting image
            let outputFilename = "output-center.png"
            try image.write(to: URL(fileURLWithPath: outputFilename))

            // Optionally open the image for visual verification on macOS
            #if os(macOS)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [outputFilename]
                try? process.run()
            #endif
        }
    }

    @Test("Draw Centered Text on Image")
    func right() async throws {
        try await ImageMagick.ResourceManager.shared.withImageMagick {
            // Create a 500x500 image with a red background
            var image = try ImageMagick.Image(width: 500, height: 500, background: .red)

            // Define text style and configuration
            let style = ImageMagick.TextConfiguration.Style(
                fontName: "Helvetica",
                fontSize: 72,
                color: .white,
                alignment: .right
            )

            // Position text in the center
            let textConfig = ImageMagick.TextConfiguration(
                text: "coenttb",
                position: .right(),
                style: style
            )

            // Render the text on the image
            image = try image.adding(text: textConfig)

            // Save the resulting image
            let outputFilename = "output-right.png"
            try image.write(to: URL(fileURLWithPath: outputFilename))

            // Optionally open the image for visual verification on macOS
            #if os(macOS)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [outputFilename]
                try? process.run()
            #endif
        }
    }
}
