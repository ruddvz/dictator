// swift-tools-version: 5.9
import PackageDescription

// A thin wrapper around llama.cpp (MIT) for Dictator's optional local cleanup model.
//
// It links llama.cpp's official prebuilt xcframework, pinned to one release by checksum, and
// nothing else: no LLM.swift (its macros pull in swift-syntax and an unpinned swift-testing),
// no chat-template engine. The only model it runs is the one the user downloads from Settings.
let package = Package(
    name: "DictatorLlama",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DictatorLlama", targets: ["DictatorLlama"])
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11900/llama-b11900-xcframework.zip",
            checksum: "613d22312cecd3915ae3edc167e95dbd37397bdb9f89ff645767622bc8eed222"
        ),
        .target(name: "DictatorLlama", dependencies: ["llama"])
    ]
)
