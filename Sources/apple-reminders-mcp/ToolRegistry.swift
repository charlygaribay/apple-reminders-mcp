import Foundation
import MCP
import RemindersCore

/// One MCP tool: the definition advertised in `tools/list` and the handler that serves it.
struct ToolHandler: Sendable {
  let tool: Tool
  let access: ToolAccess
  let run: @Sendable (ToolArguments, any RemindersStore) async throws -> any Encodable & Sendable

  /// Annotations are derived from `access` so they can't drift from the mode gating.
  init(
    name: String,
    description: String,
    inputSchema: Value,
    access: ToolAccess,
    run:
      @escaping @Sendable (ToolArguments, any RemindersStore) async throws
      -> any Encodable & Sendable
  ) {
    self.tool = Tool(
      name: name,
      description: description,
      inputSchema: inputSchema,
      annotations: .init(
        readOnlyHint: access == .read,
        destructiveHint: access == .delete,
        openWorldHint: false
      )
    )
    self.access = access
    self.run = run
  }
}

/// A tool call's arguments, decoded into a handler's own `Decodable` input type.
struct ToolArguments: Sendable {
  let values: [String: Value]

  func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
    do {
      let data = try JSONEncoder().encode(Value.object(values))
      return try JSONDecoder().decode(T.self, from: data)
    } catch let error as DecodingError {
      throw RemindersError.invalidArgument(Self.describe(error))
    }
  }

  private static func describe(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, _):
      return "missing required field '\(key.stringValue)'"
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      return "field '\(fieldPath(context))' has the wrong type or is null"
    case .dataCorrupted(let context):
      return "field '\(fieldPath(context))': \(context.debugDescription)"
    @unknown default:
      return "arguments couldn't be decoded"
    }
  }

  private static func fieldPath(_ context: DecodingError.Context) -> String {
    context.codingPath.map(\.stringValue).joined(separator: ".")
  }
}

/// Owns the tool set and is the single place errors become `isError` results.
struct ToolRegistry: Sendable {
  static let allHandlers: [ToolHandler] = [
    ListLists.handler,
    CreateList.handler,
    DeleteList.handler,
  ]

  private let store: any RemindersStore
  private let mode: ServerMode
  private let handlers: [ToolHandler]

  init(
    store: any RemindersStore,
    mode: ServerMode = .standard,
    handlers: [ToolHandler] = ToolRegistry.allHandlers
  ) {
    self.store = store
    self.mode = mode
    self.handlers = handlers
  }

  var tools: [Tool] { handlers.filter { mode.allows($0.access) }.map(\.tool) }

  func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
    guard let handler = handlers.first(where: { $0.tool.name == name }) else {
      return .failure("Unknown tool: \(name)")
    }
    // Hidden tools are rejected even when called by name.
    guard mode.allows(handler.access) else {
      return .failure(
        "Tool '\(name)' is not available: \(mode.unavailableReason(for: handler.access)).")
    }
    do {
      let output = try await handler.run(ToolArguments(values: arguments ?? [:]), store)
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
