/// Errors a store can raise. Each maps to a tool result with `isError: true`.
public enum RemindersError: Error, Equatable, Sendable {
  case accessDenied
  case notFound(kind: String, id: String)
  case invalidArgument(String)
  case readOnlyList(title: String)
  case unknownSource(title: String, available: [String])
  /// A destructive call's confirmation didn't match, so nothing was changed.
  case confirmationMismatch(expected: String, given: String)

  /// Human-readable message returned to the MCP client.
  public var message: String {
    switch self {
    case .accessDenied:
      // Without the launcher, macOS attributes the request to the MCP client and refuses it.
      return """
        Reminders access is not granted. Make sure your MCP client runs \
        apple-reminders-mcp-launch (not apple-reminders-mcp directly) and allow access when \
        macOS prompts. If access was denied before, enable apple-reminders-mcp in \
        System Settings → Privacy & Security → Reminders, then restart the server.
        """
    case .notFound(let kind, let id):
      return "\(kind) not found: \(id)"
    case .invalidArgument(let detail):
      return "Invalid argument: \(detail)"
    case .readOnlyList(let title):
      return "List '\(title)' is read-only and can't be modified."
    case .unknownSource(let title, let available):
      let names = available.map { "'\($0)'" }.joined(separator: ", ")
      return "Unknown source '\(title)'. Available sources: \(names)."
    case .confirmationMismatch(let expected, let given):
      return """
        confirmTitle '\(given)' doesn't match the list's title '\(expected)', \
        so the list was not deleted.
        """
    }
  }
}

/// Access to reminders and lists. Tool handlers depend only on this protocol.
public protocol RemindersStore: Sendable {
  func listLists() async throws -> [ReminderListDTO]

  /// Creates a list in `sourceTitle`, or in the default reminders source when `nil`.
  func createList(title: String, sourceTitle: String?) async throws -> ReminderListDTO

  /// Deletes a list and every reminder in it, provided `confirmTitle` exactly matches its title.
  /// Returns the list as it was before deletion.
  func deleteList(id: String, confirmTitle: String) async throws -> ReminderListDTO
}
