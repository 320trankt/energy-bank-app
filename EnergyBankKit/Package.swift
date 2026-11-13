// swift-tools-version:5.9
// Core logic for Energy Bank: the data model, the tunable config and the two-bank energy
// computation. Foundation only, so `swift test` runs on macOS and Linux without a simulator.
import PackageDescription

let package = Package(
    name: "EnergyBankKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EnergyBankKit", targets: ["EnergyBankKit"]),
    ],
    targets: [
        .target(name: "EnergyBankKit"),
        .testTarget(name: "EnergyBankKitTests", dependencies: ["EnergyBankKit"]),
    ]
)
