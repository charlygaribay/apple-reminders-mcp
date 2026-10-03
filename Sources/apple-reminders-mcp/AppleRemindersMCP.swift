import ArgumentParser
import Foundation
import MCP
import RemindersCore
import RemindersEventKit

@main
struct AppleRemindersMCP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: RemindersCore.serverName,
    abstract: "MCP server for Apple Reminders over stdio.",
    version: RemindersCore.serverVersion
  )

  func run() async throws {
    let server = await makeServer(registry: ToolRegistry(store: EventKitStore()))
    // stdout carries MCP frames only; diagnostics go to stderr.
    try await server.start(transport: StdioTransport())
    log("server started")
    await server.waitUntilCompleted()
  }
}

func log(_ message: String) {
  FileHandle.standardError.write(Data("[\(RemindersCore.serverName)] \(message)\n".utf8))
}
