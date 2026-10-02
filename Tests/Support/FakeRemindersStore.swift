import RemindersCore

/// In-memory `RemindersStore` for unit tests. Set `failure` to make every call throw it.
public actor FakeRemindersStore: RemindersStore {
  public var lists: [ReminderListDTO]
  public var failure: RemindersError?

  public init(lists: [ReminderListDTO] = [], failure: RemindersError? = nil) {
    self.lists = lists
    self.failure = failure
  }

  public func listLists() async throws -> [ReminderListDTO] {
    try throwIfFailing()
    return lists
  }

  private func throwIfFailing() throws {
    if let failure { throw failure }
  }
}
