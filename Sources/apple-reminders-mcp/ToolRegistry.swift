import Foundation
import MCP
import RemindersCore

/// One MCP tool: the definition advertised in `tools/list` and the handler that serves it.
struct ToolHandler: Sendable {
  let tool: Tool
  let run: @Sendable ([String: Value], any RemindersStore) async throws -> any Encodable & Sendable
}

/// Owns the tool set and is the single place errors become `isError` results.
struct ToolRegistry: Sendable {
  static let allHandlers: [ToolHandler] = [
    ListLists.handler
  ]

  private let store: any RemindersStore
  private let handlers: [ToolHandler]

  init(store: any RemindersStore, handlers: [ToolHandler] = ToolRegistry.allHandlers) {
    self.store = store
    self.handlers = handlers
  }

  var tools: [Tool] { handlers.map(\.tool) }

  func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
    guard let handler = handlers.first(where: { $0.tool.name == name }) else {
      return .failure("Unknown tool: \(name)")
    }
    do {
      let output = try await handler.run(arguments ?? [:], store)
      return .init(content: [.plainText(try Self.encode(output))])
    } catch let error as RemindersError {
      return .failure(error.message)
    } catch {
      return .failure("Unexpected error: \(error)")
    }
  }

  private static func encode(_ value: any Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

extension CallTool.Result {
  fileprivate static func failure(_ message: String) -> Self {
    .init(content: [.plainText(message)], isError: true)
  }
}

extension Tool.Content {
  fileprivate static func plainText(_ text: String) -> Self {
    .text(text: text, annotations: nil, _meta: nil)
  }
}

/// Builds the MCP server with this registry's tools wired in.
func makeServer(registry: ToolRegistry) async -> Server {
  let server = Server(
    name: RemindersCore.serverName,
    version: RemindersCore.serverVersion,
    capabilities: .init(tools: .init(listChanged: false))
  )
  await server.withMethodHandler(ListTools.self) { _ in .init(tools: registry.tools) }
  await server.withMethodHandler(CallTool.self) { params in
    await registry.call(name: params.name, arguments: params.arguments)
  }
  return server
}
