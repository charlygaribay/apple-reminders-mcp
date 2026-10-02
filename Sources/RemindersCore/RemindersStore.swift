/// Errors a store can raise. Each maps to a tool result with `isError: true`.
public enum RemindersError: Error, Equatable, Sendable {
  case accessDenied
  case notFound(kind: String, id: String)
  case invalidArgument(String)
  case readOnlyList(title: String)

  /// Human-readable message returned to the MCP client.
  public var message: String {
    switch self {
    case .accessDenied:
      // The grant belongs to the process that launched the server, not the binary itself.
      return """
        Reminders access is not granted. Open System Settings → Privacy & Security → Reminders, \
        give full access to the app that launched this server (e.g. Terminal or Claude), \
        then restart the server.
        """
    case .notFound(let kind, let id):
      return "\(kind) not found: \(id)"
    case .invalidArgument(let detail):
      return "Invalid argument: \(detail)"
    case .readOnlyList(let title):
      return "List '\(title)' is read-only and can't be modified."
    }
  }
}

/// Access to reminders and lists. Tool handlers depend only on this protocol.
public protocol RemindersStore: Sendable {
  func listLists() async throws -> [ReminderListDTO]
}
