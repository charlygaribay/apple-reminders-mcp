import Foundation
import MCP
import System

/// Integration tests run only when explicitly requested, because they use real Reminders.
let integrationEnabled = ProcessInfo.processInfo.environment["REMINDERS_MCP_INTEGRATION"] == "1"

/// The built launcher + server, driven over stdio by an MCP client: exactly what clients run.
///
/// Tests can't use EventKit in-process: macOS attributes the test runner's requests to the
/// app that launched it, which has no Reminders usage description. The launcher makes the
/// server its own responsible process, so only the server binary needs the grant.
struct ServerProcess {
  let client: Client
  private let process: Process

  static func start(arguments: [String] = []) async throws -> ServerProcess {
    let toServer = Pipe()
    let fromServer = Pipe()
    let process = Process()
    process.executableURL = binDirectory.appendingPathComponent("apple-reminders-mcp-launch")
    process.arguments = arguments
    process.standardInput = toServer
    process.standardOutput = fromServer
    try process.run()

    let transport = StdioTransport(
      input: FileDescriptor(rawValue: fromServer.fileHandleForReading.fileDescriptor),
      output: FileDescriptor(rawValue: toServer.fileHandleForWriting.fileDescriptor)
    )
    let client = Client(name: "integration-tests", version: "0")
    _ = try await client.connect(transport: transport)
    return ServerProcess(client: client, process: process)
  }

  func stop() async {
    await client.disconnect()
    process.terminate()
    process.waitUntilExit()
  }

  /// `REMINDERS_MCP_BIN_DIR`, or this package's debug build directory.
  private static var binDirectory: URL {
    if let dir = ProcessInfo.processInfo.environment["REMINDERS_MCP_BIN_DIR"] {
      return URL(fileURLWithPath: dir)
    }
    return URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // IntegrationTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // package root
      .appendingPathComponent(".build/debug")
  }
}
