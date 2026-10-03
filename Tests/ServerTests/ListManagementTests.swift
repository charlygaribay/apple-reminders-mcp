import MCP
import RemindersCore
import TestSupport
import Testing

@testable import apple_reminders_mcp

private let work = ReminderListDTO(
  id: "L-work", title: "Work", sourceTitle: "iCloud", incompleteCount: 2)

@Suite struct ToolGatingTests {
  @Test func standardModeHidesDeleteList() async throws {
    let names = try await TestClient(store: FakeRemindersStore()).toolNames()
    #expect(names.isSuperset(of: ["list_lists", "create_list"]))
    #expect(!names.contains("delete_list"))
  }

  @Test func allowDeleteModeExposesDeleteListAsDestructive() async throws {
    let client = try await TestClient(store: FakeRemindersStore(), mode: .allowDelete)
    let tool = try #require(try await client.listTools().first { $0.name == "delete_list" })
    #expect(tool.annotations.destructiveHint == true)
    #expect(tool.annotations.readOnlyHint == false)
  }

  @Test func createListIsAWriteNotADestructiveTool() async throws {
    let client = try await TestClient(store: FakeRemindersStore())
    let tool = try #require(try await client.listTools().first { $0.name == "create_list" })
    #expect(tool.annotations.readOnlyHint == false)
    #expect(tool.annotations.destructiveHint == false)
  }

  @Test func hiddenDeleteListIsRejectedByName() async throws {
    let store = FakeRemindersStore(lists: [work])
    let client = try await TestClient(store: store)
    let (text, isError) = try await client.call(
      "delete_list", ["id": "L-work", "confirmTitle": "Work"])
    #expect(isError)
    #expect(text.contains("--allow-delete"))
    #expect(await store.lists == [work])
  }
}

@Suite struct CreateListTests {
  @Test func createsInDefaultSource() async throws {
    let store = FakeRemindersStore(sources: ["iCloud", "On My Mac"])
    let client = try await TestClient(store: store)
    let result = try await client.callDecoding(
      ListResult.self, "create_list", ["title": "Groceries"])
    #expect(result.list.title == "Groceries")
    #expect(result.list.sourceTitle == "iCloud")
    #expect(await store.lists.map(\.id) == [result.list.id])
  }

  @Test func createsInNamedSource() async throws {
    let client = try await TestClient(store: FakeRemindersStore(sources: ["iCloud", "On My Mac"]))
    let result = try await client.callDecoding(
      ListResult.self, "create_list", ["title": "Local", "sourceTitle": "On My Mac"])
    #expect(result.list.sourceTitle == "On My Mac")
  }

  @Test func trimsTitle() async throws {
    let client = try await TestClient(store: FakeRemindersStore())
    let result = try await client.callDecoding(
      ListResult.self, "create_list", ["title": "  Groceries \n"])
    #expect(result.list.title == "Groceries")
  }

  @Test(arguments: ["", "   ", "\n\t"])
  func rejectsBlankTitle(title: String) async throws {
    let store = FakeRemindersStore()
    let (text, isError) = try await TestClient(store: store).call(
      "create_list", ["title": .string(title)])
    #expect(isError)
    #expect(text.contains("title"))
    #expect(await store.lists.isEmpty)
  }

  @Test func rejectsMissingTitle() async throws {
    let (text, isError) = try await TestClient(store: FakeRemindersStore()).call("create_list", [:])
    #expect(isError)
    #expect(text.contains("title"))
  }

  @Test func rejectsWrongTypedTitle() async throws {
    let (text, isError) = try await TestClient(store: FakeRemindersStore()).call(
      "create_list", ["title": 42])
    #expect(isError)
    #expect(text.contains("title"))
  }

  @Test func unknownSourceNamesTheAvailableOnes() async throws {
    let client = try await TestClient(store: FakeRemindersStore(sources: ["iCloud", "On My Mac"]))
    let (text, isError) = try await client.call(
      "create_list", ["title": "X", "sourceTitle": "Exchange"])
    #expect(isError)
    #expect(text.contains("Exchange"))
    #expect(text.contains("iCloud"))
    #expect(text.contains("On My Mac"))
  }
}

@Suite struct DeleteListTests {
  @Test func matchingTitleDeletesTheList() async throws {
    let store = FakeRemindersStore(lists: [work])
    let client = try await TestClient(store: store, mode: .allowDelete)
    let result = try await client.callDecoding(
      DeletedListResult.self, "delete_list", ["id": "L-work", "confirmTitle": "Work"])
    #expect(result.deleted == work)
    #expect(await store.lists.isEmpty)
  }

  @Test(arguments: ["work", "Work ", "Personal", ""])
  func mismatchedTitleKeepsTheList(confirmTitle: String) async throws {
    let store = FakeRemindersStore(lists: [work])
    let client = try await TestClient(store: store, mode: .allowDelete)
    let (text, isError) = try await client.call(
      "delete_list", ["id": "L-work", "confirmTitle": .string(confirmTitle)])
    #expect(isError)
    #expect(text.contains("'Work'"))
    #expect(await store.lists == [work])
  }

  @Test func unknownIdIsNotFound() async throws {
    let client = try await TestClient(store: FakeRemindersStore(), mode: .allowDelete)
    let (text, isError) = try await client.call(
      "delete_list", ["id": "nope", "confirmTitle": "Work"])
    #expect(isError)
    #expect(text == "list not found: nope")
  }

  @Test func immutableListIsRefused() async throws {
    let store = FakeRemindersStore(lists: [work], immutableListIDs: ["L-work"])
    let client = try await TestClient(store: store, mode: .allowDelete)
    let (text, isError) = try await client.call(
      "delete_list", ["id": "L-work", "confirmTitle": "Work"])
    #expect(isError)
    #expect(text.contains("read-only"))
    #expect(await store.lists == [work])
  }

  @Test func missingConfirmTitleIsRejected() async throws {
    let store = FakeRemindersStore(lists: [work])
    let client = try await TestClient(store: store, mode: .allowDelete)
    let (text, isError) = try await client.call("delete_list", ["id": "L-work"])
    #expect(isError)
    #expect(text.contains("confirmTitle"))
    #expect(await store.lists == [work])
  }
}

@Suite struct RenameListTests {
  @Test func renamesAndReturnsTheList() async throws {
    let store = FakeRemindersStore(lists: [work])
    let client = try await TestClient(store: store)
    let result = try await client.callDecoding(
      ListResult.self, "rename_list", ["id": "L-work", "title": " Office "])
    #expect(result.list.id == "L-work")
    #expect(result.list.title == "Office")
    #expect(await store.lists.map(\.title) == ["Office"])
  }

  @Test func isAWriteTool() async throws {
    let client = try await TestClient(store: FakeRemindersStore())
    let tool = try #require(try await client.listTools().first { $0.name == "rename_list" })
    #expect(tool.annotations.readOnlyHint == false)
    #expect(tool.annotations.destructiveHint == false)
  }

  @Test func blankTitleIsRejected() async throws {
    let store = FakeRemindersStore(lists: [work])
    let (text, isError) = try await TestClient(store: store).call(
      "rename_list", ["id": "L-work", "title": "  "])
    #expect(isError)
    #expect(text.contains("'title' must not be empty"))
    #expect(await store.lists == [work])
  }

  @Test func unknownIdIsNotFound() async throws {
    let (text, isError) = try await TestClient(store: FakeRemindersStore()).call(
      "rename_list", ["id": "nope", "title": "X"])
    #expect(isError)
    #expect(text == "list not found: nope")
  }

  @Test func immutableListIsRefused() async throws {
    let store = FakeRemindersStore(lists: [work], immutableListIDs: ["L-work"])
    let (text, isError) = try await TestClient(store: store).call(
      "rename_list", ["id": "L-work", "title": "Office"])
    #expect(isError)
    #expect(text.contains("read-only"))
    #expect(await store.lists == [work])
  }
}
