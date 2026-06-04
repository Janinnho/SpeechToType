// swift-tools-version: 5.9
import PackageDescription

// Wraps the Microsoft Cognitive Services Speech SDK (macOS xcframework) as an SPM
// binary target. The binary is downloaded by SPM from Microsoft's official storage on
// first resolve and cached locally — it is NOT committed to this repository.
//
// To bump the SDK version: update the URL and recompute the checksum with
//   swift package compute-checksum MicrosoftCognitiveServicesSpeech-MacOSXCFramework-<version>.zip
let package = Package(
    name: "MicrosoftSpeechSDK",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "MicrosoftSpeechSDK", targets: ["MicrosoftCognitiveServicesSpeech"])
    ],
    targets: [
        .binaryTarget(
            name: "MicrosoftCognitiveServicesSpeech",
            url: "https://csspeechstorage.blob.core.windows.net/drop/1.50.0/MicrosoftCognitiveServicesSpeech-MacOSXCFramework-1.50.0.zip",
            checksum: "3b748dd2222c7ae06567878467bbc39b17a8dea015284a9a3117b0ea12a55a0b"
        )
    ]
)
