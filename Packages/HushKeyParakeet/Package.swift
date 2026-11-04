// swift-tools-version: 6.2
import PackageDescription

// A thin wrapper around FluidAudio's Parakeet speech recognition.
//
// It exists so HushKey can turn FluidAudio's package traits off (`traits: []`): the default
// `TTS` trait bundles a G2P lexicon generated from GPL-3.0 espeak-ng data, which HushKey must
// not ship (AGENTS.md), and the `Diarizer` and `NemoTextProcessing` traits add code HushKey
// never calls. An Xcode project can't set a package's traits; a local package can.
let package = Package(
    name: "HushKeyParakeet",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HushKeyParakeet", targets: ["HushKeyParakeet"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.2", traits: [])
    ],
    targets: [
        .target(
            name: "HushKeyParakeet",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .testTarget(name: "HushKeyParakeetTests", dependencies: ["HushKeyParakeet"])
    ]
)
