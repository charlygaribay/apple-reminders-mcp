/// Domain types shared by the store and the MCP tool layer.
public enum RemindersCore {
  public static let serverName = "apple-reminders-mcp"
  public static let serverVersion = "0.1.0"
}

/// A reminder list (an EventKit calendar of type `.reminder`).
public struct ReminderListDTO: Codable, Equatable, Sendable {
  public var id: String
  public var title: String
  /// The account the list lives in, e.g. "iCloud" or "On My Mac".
  public var sourceTitle: String
  public var incompleteCount: Int

  public init(id: String, title: String, sourceTitle: String, incompleteCount: Int) {
    self.id = id
    self.title = title
    self.sourceTitle = sourceTitle
    self.incompleteCount = incompleteCount
  }
}
