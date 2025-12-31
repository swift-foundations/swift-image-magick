# swift-image-magick

[![CI](https://github.com/coenttb/swift-image-magick/workflows/CI/badge.svg)](https://github.com/coenttb/swift-image-magick/actions/workflows/ci.yml)
![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Swift wrapper for ImageMagick C library, enabling image manipulation and processing with a Swift-native API.

## Features

- Swift-friendly interface for ImageMagick.
- Perform operations like:
  - Text Metrics: Calculate text properties (width, height, ascender, descender, bounding box, etc.).
  - Image Manipulation: Resize, transform, and process images.

## Installation

### Prerequisites

1. **ImageMagick** must be installed on your system.

   - On macOS (Homebrew):
     ```bash
     brew install imagemagick
     ```

   - On Linux (Debian/Ubuntu):
     ```bash
     sudo apt-get update
     sudo apt-get install libmagickwand-dev
     ```

2. **Swift Package Manager** Add `SwiftImageMagick` to your `Package.swift` dependencies:

```swift

let package = Package(
    name: "YourProject",
    dependencies: [
        .package(url: "https://github.com/coenttb/swift-image-magick.git", branch: "main")
    ],
    targets: [
        .target(name: "YourProject", dependencies: ["SwiftImageMagick"])
    ]
)
```

## Related Packages

This package has no dependencies and is not currently used by other packages in the ecosystem.

## Contributing

Contributions are welcome. Please open an issue or submit a pull request.

## License

This project is licensed by coenttb under the Apache 2.0 License. See [LICENSE](LICENSE) for details.
