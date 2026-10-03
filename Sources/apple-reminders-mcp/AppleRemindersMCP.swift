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

  @Flag(help: "Expose the tools that permanently delete reminders and lists.")
  var allowDelete = false

  func run() async throws {
    let mode = ServerMode.resolve(
      allowDeleteFlag: allowDelete, environment: ProcessInfo.processInfo.environment)
    let registry = ToolRegistry(store: EventKitStore(), mode: mode)
    let server = await makeServer(registry: registry)
    // stdout carries MCP frames only; diagnostics go to stderr.
    try await server.start(transport: StdioTransport())
    log("server started (mode: \(mode))")
    await server.waitUntilCompleted()
  }
}

func log(_ message: String) {
  FileHandle.standardError.write(Data("[\(RemindersCore.serverName)] \(message)\n".utf8))
}
