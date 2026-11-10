// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ptts",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ptts", targets: ["PhononTTS"]),
    ],
    targets: [
        // xn-ptts 0.4.2 plus the model publisher's flow-steps patch. This exact runtime is
        // required by itsmechico/phonon-40m-en-coreml's additional flow-step graph.
        .binaryTarget(
            name: "PhononCore",
            url: "https://huggingface.co/itsmechico/phonon-core-runtime/resolve/11d38f27745061df2b8372a8a3f28061b8046b0b/PhononCore.xcframework.zip",
            checksum: "96280157cd0a1e327b4a3ad45ab20c27c3ace35c9cfa3441dcc5e56081e19db6"
        ),
        .target(
            name: "PhononTTS",
            dependencies: ["PhononCore"],
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
