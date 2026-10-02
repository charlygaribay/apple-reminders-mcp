import Foundation
import MCP
import RemindersCore

@testable import apple_reminders_mcp

/// Runs a real MCP client against the server over an in-memory transport.
struct TestClient {
  let client: Client
  let server: Server

  init(store: any RemindersStore) async throws {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    server = await makeServer(registry: ToolRegistry(store: store))
    try await server.start(transport: serverTransport)
    client = Client(name: "test-client", version: "0")
    _ = try await client.connect(transport: clientTransport)
  }

  func listTools() async throws -> [Tool] {
    try await client.listTools().tools
  }

  /// Calls a tool and returns its single text content block.
  func call(_ name: String, _ arguments: [String: Value]? = nil) async throws -> (
    text: String, isError: Bool
  ) {
    let result = try await client.callTool(name: name, arguments: arguments)
    guard result.content.count == 1, case .text(let text, _, _) = result.content[0] else {
      throw TestClientError.unexpectedContent(result.content)
    }
    return (text, result.isError ?? false)
  }

  /// Calls a tool expected to succeed and decodes its JSON payload.
  func callDecoding<T: Decodable>(
    _ type: T.Type, _ name: String, _ arguments: [String: Value]? = nil
  ) async throws -> T {
    let (text, isError) = try await call(name, arguments)
    guard !isError else { throw TestClientError.toolError(text) }
    return try JSONDecoder().decode(T.self, from: Data(text.utf8))
  }
}

enum TestClientError: Error {
  case unexpectedContent([Tool.Content])
  case toolError(String)
}
