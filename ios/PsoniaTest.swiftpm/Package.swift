// swift-tools-version: 5.9
// Psonia price-reader test (2026-10-30). Open this folder in Xcode, pick your iPhone, press Run.
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "PsoniaTest",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "PsoniaTest",
            targets: ["AppModule"],
            bundleIdentifier: "com.panosfrantzis.psoniatest",
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .carrot),
            accentColor: .presetColor(.green),
            supportedDeviceFamilies: [.phone],
            supportedInterfaceOrientations: [.portrait]
        )
    ],
    targets: [
        .executableTarget(name: "AppModule", path: ".", resources: [.process("Resources")])
    ]
)
