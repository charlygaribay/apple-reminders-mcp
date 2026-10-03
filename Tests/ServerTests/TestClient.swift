import MCP
import RemindersCore
import TestSupport

@testable import apple_reminders_mcp

/// Runs a real MCP client against the server over an in-memory transport.
struct TestClient {
  let client: Client
  let server: Server

  init(store: any RemindersStore, mode: ServerMode = .standard) async throws {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    server = await makeServer(registry: ToolRegistry(store: store, mode: mode))
    try await server.start(transport: serverTransport)
    client = Client(name: "test-client", version: "0")
    _ = try await client.connect(transport: clientTransport)
  }

  func listTools() async throws -> [Tool] {
    try await client.listTools().tools
  }

  func toolNames() async throws -> Set<String> {
    Set(try await listTools().map(\.name))
  }

  func call(_ name: String, _ arguments: [String: Value]? = nil) async throws -> (
    text: String, isError: Bool
  ) {
    try await client.callText(name, arguments)
  }

  func callDecoding<T: Decodable & Sendable>(
    _ type: T.Type, _ name: String, _ arguments: [String: Value]? = nil
  ) async throws -> T {
    try await client.callDecoding(type, name, arguments)
  }
}
