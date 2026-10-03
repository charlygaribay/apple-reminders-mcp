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

/// Reminder priority as shown in Reminders.app.
public enum Priority: String, Codable, CaseIterable, Sendable {
  case none, low, medium, high

  /// EventKit stores 0 (none) or 1–9, where 1 is highest. Reminders.app writes 1, 5, and 9;
  /// other apps may write anything in range, so bucket it the way Reminders.app displays it.
  public init(eventKitValue: Int) {
    switch eventKitValue {
    case 1...4: self = .high
    case 5: self = .medium
    case 6...9: self = .low
    default: self = .none
    }
  }

  public var eventKitValue: Int {
    switch self {
    case .none: 0
    case .low: 9
    case .medium: 5
    case .high: 1
    }
  }
}
