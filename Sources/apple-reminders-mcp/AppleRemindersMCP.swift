import ArgumentParser
import Foundation
import MCP
import RemindersCore

@main
struct AppleRemindersMCP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: RemindersCore.serverName,
    abstract: "MCP server for Apple Reminders over stdio.",
    version: RemindersCore.serverVersion
  )

  func run() async throws {
    let server = Server(
      name: RemindersCore.serverName,
      version: RemindersCore.serverVersion,
      capabilities: .init(tools: .init(listChanged: false))
    )
    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: [])
    }

    // stdout carries MCP frames only; diagnostics go to stderr.
    try await server.start(transport: StdioTransport())
    log("server started")
    await server.waitUntilCompleted()
  }
}

func log(_ message: String) {
  FileHandle.standardError.write(Data("[\(RemindersCore.serverName)] \(message)\n".utf8))
}
