import EventKit
import RemindersCore

/// `RemindersStore` backed by EventKit. The only type in the package that touches Reminders data.
public actor EventKitStore: RemindersStore {
  private let store = EKEventStore()
  private var hasAccess = false

  public init() {}

  public func listLists() async throws -> [ReminderListDTO] {
    try await ensureAccess()
    let counts = await incompleteCountsByList()
    return store.calendars(for: .reminder)
      .map { ReminderListDTO($0, incompleteCount: counts[$0.calendarIdentifier] ?? 0) }
      .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
  }

  // MARK: - Access

  private func ensureAccess() async throws {
    if hasAccess { return }
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .fullAccess:
      hasAccess = true
    case .notDetermined:
      // Prompts on first use. macOS attributes the prompt to the app that launched the server.
      guard try await store.requestFullAccessToReminders() else {
        throw RemindersError.accessDenied
      }
      hasAccess = true
    case .denied, .restricted, .writeOnly:
      throw RemindersError.accessDenied
    @unknown default:
      throw RemindersError.accessDenied
    }
  }

  // MARK: - Fetching

  private func incompleteCountsByList() async -> [String: Int] {
    let predicate = store.predicateForIncompleteReminders(
      withDueDateStarting: nil, ending: nil, calendars: nil)
    return await withCheckedContinuation { continuation in
      // EKReminder isn't Sendable, so reduce to plain values inside the callback.
      store.fetchReminders(matching: predicate) { reminders in
        var counts: [String: Int] = [:]
        for reminder in reminders ?? [] {
          if let id = reminder.calendar?.calendarIdentifier { counts[id, default: 0] += 1 }
        }
        continuation.resume(returning: counts)
      }
    }
  }
}
