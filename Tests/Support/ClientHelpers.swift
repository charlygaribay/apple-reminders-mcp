import Foundation
import MCP

extension Client {
  /// Calls a tool and returns its single text content block.
  nonisolated public func callText(_ name: String, _ arguments: [String: Value]? = nil) async throws
    -> (
      text: String, isError: Bool
    )
  {
    let result = try await callTool(name: name, arguments: arguments)
    guard result.content.count == 1, case .text(let text, _, _) = result.content[0] else {
      throw ClientHelperError.unexpectedContent(result.content)
    }
    return (text, result.isError ?? false)
  }

  /// Calls a tool expected to succeed and decodes its JSON payload.
  nonisolated public func callDecoding<T: Decodable & Sendable>(
    _ type: T.Type, _ name: String, _ arguments: [String: Value]? = nil
  ) async throws -> T {
    let (text, isError) = try await callText(name, arguments)
    guard !isError else { throw ClientHelperError.toolError(text) }
    return try JSONDecoder().decode(T.self, from: Data(text.utf8))
  }
}

public enum ClientHelperError: Error {
  case unexpectedContent([Tool.Content])
  case toolError(String)
}
