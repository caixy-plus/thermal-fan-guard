// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ThermalFanGuard",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ThermalFanGuardCore", targets: ["ThermalFanGuardCore"]),
    .executable(name: "thermal-fan-guard", targets: ["ThermalFanGuard"]),
    .executable(name: "ThermalFanGuardApp", targets: ["ThermalFanGuardApp"]),
  ],
  dependencies: [
    .package(path: "../thermal-fan-guard-vendor"),
  ],
  targets: [
    .target(name: "ThermalFanGuardCore"),
    .executableTarget(
      name: "ThermalFanGuard",
      dependencies: [
        "ThermalFanGuardCore",
        .product(name: "SMCKit", package: "thermal-fan-guard-vendor"),
        .product(name: "SMCFanKit", package: "thermal-fan-guard-vendor"),
      ]
    ),
    .executableTarget(
      name: "ThermalFanGuardApp",
      dependencies: ["ThermalFanGuardCore"]
    ),
    .testTarget(
      name: "ThermalFanGuardTests",
      dependencies: ["ThermalFanGuardCore"]
    ),
  ]
)
