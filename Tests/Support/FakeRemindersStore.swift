import Foundation
import RemindersCore

/// In-memory `RemindersStore` for unit tests. Set `failure` to make every call throw it.
public actor FakeRemindersStore: RemindersStore {
  public var lists: [ReminderListDTO]
  public var failure: RemindersError?
  /// Account names lists can be created in; the first is the default.
  public var sources: [String]
  /// Lists that can't be modified or deleted (e.g. shared or subscribed lists).
  public var immutableListIDs: Set<String>

  public init(
    lists: [ReminderListDTO] = [],
    failure: RemindersError? = nil,
    sources: [String] = ["iCloud"],
    immutableListIDs: Set<String> = []
  ) {
    self.lists = lists
    self.failure = failure
    self.sources = sources
    self.immutableListIDs = immutableListIDs
  }

  public func listLists() async throws -> [ReminderListDTO] {
    try throwIfFailing()
    return lists
  }

  public func createList(title: String, sourceTitle: String?) async throws -> ReminderListDTO {
    try throwIfFailing()
    let source = sourceTitle ?? sources[0]
    guard sources.contains(source) else {
      throw RemindersError.unknownSource(title: source, available: sources)
    }
    let list = ReminderListDTO(
      id: "L-\(UUID().uuidString)", title: title, sourceTitle: source, incompleteCount: 0)
    lists.append(list)
    return list
  }

  public func renameList(id: String, title: String) async throws -> ReminderListDTO {
    try throwIfFailing()
    let index = try mutableListIndex(id: id)
    lists[index].title = title
    return lists[index]
  }

  public func deleteList(id: String, confirmTitle: String) async throws -> ReminderListDTO {
    try throwIfFailing()
    let index = try mutableListIndex(id: id)
    let list = lists[index]
    guard confirmTitle == list.title else {
      throw RemindersError.confirmationMismatch(expected: list.title, given: confirmTitle)
    }
    lists.remove(at: index)
    return list
  }

  private func mutableListIndex(id: String) throws -> Int {
    guard let index = lists.firstIndex(where: { $0.id == id }) else {
      throw RemindersError.notFound(kind: "list", id: id)
    }
    guard !immutableListIDs.contains(id) else {
      throw RemindersError.readOnlyList(title: lists[index].title)
    }
    return index
  }

  private func throwIfFailing() throws {
    if let failure { throw failure }
  }
}
