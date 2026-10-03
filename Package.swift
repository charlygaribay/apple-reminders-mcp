// swift-tools-version: 6.0

import Foundation
import PackageDescription

// Embedding an Info.plist gives the binary a Reminders usage description; without one,
// macOS can refuse the access request for a bare command-line tool.
let infoPlist = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .appendingPathComponent("Sources/apple-reminders-mcp/Info.plist").path

let package = Package(
  name: "apple-reminders-mcp",
  platforms: [
    // requestFullAccessToReminders() is macOS 14+.
    .macOS(.v14)
  ],
  products: [
    .executable(name: "apple-reminders-mcp", targets: ["apple-reminders-mcp"]),
    // What MCP clients launch; see Sources/apple-reminders-mcp-launch/Launcher.swift.
    .executable(name: "apple-reminders-mcp-launch", targets: ["apple-reminders-mcp-launch"]),
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
      ],
      exclude: ["Info.plist"],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
          "-Xlinker", infoPlist,
        ])
      ]
    ),
    .executableTarget(name: "apple-reminders-mcp-launch"),
    .testTarget(
      name: "RemindersCoreTests",
      dependencies: ["RemindersCore"]
    ),
    .target(
      name: "TestSupport",
      dependencies: ["RemindersCore", .product(name: "MCP", package: "swift-sdk")],
      path: "Tests/Support"
    ),
    .testTarget(
      name: "LauncherTests",
      dependencies: ["apple-reminders-mcp-launch"]
    ),
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        "RemindersCore",
        "TestSupport",
        .product(name: "MCP", package: "swift-sdk"),
      ]
    ),
    .testTarget(
      name: "ServerTests",
      dependencies: [
        "apple-reminders-mcp",
        "TestSupport",
        .product(name: "MCP", package: "swift-sdk"),
      ]
    ),
  ]
)
