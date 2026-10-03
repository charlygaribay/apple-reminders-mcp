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

  public func createList(title: String, sourceTitle: String?) async throws -> ReminderListDTO {
    try await ensureAccess()
    let list = EKCalendar(for: .reminder, eventStore: store)
    list.title = title
    list.source = try source(named: sourceTitle)
    try store.saveCalendar(list, commit: true)
    return ReminderListDTO(list, incompleteCount: 0)
  }

  public func deleteList(id: String, confirmTitle: String) async throws -> ReminderListDTO {
    try await ensureAccess()
    let list = try reminderList(id: id)
    guard !list.isImmutable else { throw RemindersError.readOnlyList(title: list.title) }
    guard confirmTitle == list.title else {
      throw RemindersError.confirmationMismatch(expected: list.title, given: confirmTitle)
    }
    let counts = await incompleteCountsByList()
    let deleted = ReminderListDTO(list, incompleteCount: counts[list.calendarIdentifier] ?? 0)
    try store.removeCalendar(list, commit: true)
    return deleted
  }

  // MARK: - Access

  private func ensureAccess() async throws {
    if hasAccess { return }
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .fullAccess:
      hasAccess = true
    case .notDetermined:
      // Prompts on first use. Started via the launcher, macOS asks on behalf of this binary.
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

  // MARK: - Lookup

  private func reminderList(id: String) throws -> EKCalendar {
    // calendar(withIdentifier:) also finds event calendars, which aren't reminder lists.
    guard let list = store.calendar(withIdentifier: id),
      list.allowedEntityTypes.contains(.reminder)
    else {
      throw RemindersError.notFound(kind: "list", id: id)
    }
    return list
  }

  /// The named account, or the one holding the default reminders list when `name` is nil.
  private func source(named name: String?) throws -> EKSource {
    // Only accounts that already hold reminder lists can take new ones.
    let candidates = store.calendars(for: .reminder).compactMap(\.source)
    let defaultSource = store.defaultCalendarForNewReminders()?.source
    guard let name else {
      guard let source = defaultSource ?? candidates.first else {
        throw RemindersError.invalidArgument("no account available for new reminder lists")
      }
      return source
    }
    if let source = candidates.first(where: { $0.title == name }) { return source }
    let available = Set(candidates.map(\.title)).sorted()
    throw RemindersError.unknownSource(title: name, available: available)
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
