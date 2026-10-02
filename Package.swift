// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "apple-reminders-mcp",
  platforms: [
    // requestFullAccessToReminders() is macOS 14+.
    .macOS(.v14)
  ],
  products: [
    .executable(name: "apple-reminders-mcp", targets: ["apple-reminders-mcp"])
  ],
  dependencies: [
    // Pre-1.0: pin to the minor version so API changes don't arrive unannounced.
    .package(
      url: "https://github.com/modelcontextprotocol/swift-sdk.git",
      .upToNextMinor(from: "0.12.1")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
  ],
  targets: [
    .target(name: "RemindersCore"),
    .target(
      name: "RemindersEventKit",
      dependencies: ["RemindersCore"],
      linkerSettings: [.linkedFramework("EventKit")]
    ),
    .executableTarget(
      name: "apple-reminders-mcp",
      dependencies: [
        "RemindersCore",
        "RemindersEventKit",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "RemindersCoreTests",
      dependencies: ["RemindersCore"]
    ),
  ]
)
