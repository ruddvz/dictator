// swift-tools-version: 6.2
import PackageDescription

// A thin wrapper around FluidAudio's Parakeet speech recognition.
//
// It exists so Dictator can turn FluidAudio's package traits off (`traits: []`): the default
// `TTS` trait bundles a G2P lexicon generated from GPL-3.0 espeak-ng data, which Dictator must
// not ship (AGENTS.md), and the `Diarizer` and `NemoTextProcessing` traits add code Dictator
// never calls. An Xcode project can't set a package's traits; a local package can.
let package = Package(
    name: "DictatorParakeet",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DictatorParakeet", targets: ["DictatorParakeet"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.4", traits: [])
    ],
    targets: [
        .target(
            name: "DictatorParakeet",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .testTarget(name: "DictatorParakeetTests", dependencies: ["DictatorParakeet"])
    ]
)
