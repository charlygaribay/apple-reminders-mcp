import MCP
import RemindersCore
import TestSupport
import Testing

@testable import apple_reminders_mcp

@Suite struct ListListsTests {
  let sampleLists = [
    ReminderListDTO(id: "L1", title: "Personal", sourceTitle: "iCloud", incompleteCount: 3),
    ReminderListDTO(id: "L2", title: "Work", sourceTitle: "iCloud", incompleteCount: 0),
  ]

  @Test func advertisedAsReadOnly() async throws {
    let client = try await TestClient(store: FakeRemindersStore())
    let tool = try #require(try await client.listTools().first { $0.name == "list_lists" })
    #expect(tool.annotations.readOnlyHint == true)
  }

  @Test func returnsEveryList() async throws {
    let client = try await TestClient(store: FakeRemindersStore(lists: sampleLists))
    let result = try await client.callDecoding(ListListsResult.self, "list_lists")
    #expect(result.lists == sampleLists)
  }

  @Test func accessDeniedBecomesToolErrorWithFix() async throws {
    let client = try await TestClient(store: FakeRemindersStore(failure: .accessDenied))
    let (text, isError) = try await client.call("list_lists")
    #expect(isError)
    #expect(text.contains("Privacy & Security"))
  }
}

@Suite struct DispatchTests {
  @Test func unknownToolBecomesToolError() async throws {
    let client = try await TestClient(store: FakeRemindersStore())
    let (text, isError) = try await client.call("no_such_tool")
    #expect(isError)
    #expect(text.contains("no_such_tool"))
  }
}
