import MCP
import RemindersCore
import TestSupport
import Testing

private struct DeliberateFailure: Error {}

@Suite(.enabled(if: integrationEnabled), .serialized)
struct ListManagementEndToEndTests {
  @Test func createdListIsListedAndRemovedAfterwards() async throws {
    try await ServerProcess.with { server in
      let listID = try await server.withThrowawayList { list in
        let found = try #require(
          try await server.client.callDecoding(ListsPayload.self, "list_lists").lists
            .first { $0.id == list.id })
        #expect(found.title == list.title)
        #expect(found.incompleteCount == 0)
        return list.id
      }
      #expect(try await !server.listIDs().contains(listID))
    }
  }

  @Test func teardownRunsWhenTheTestBodyFails() async throws {
    try await ServerProcess.with { server in
      var listID: String?
      await #expect(throws: DeliberateFailure.self) {
        try await server.withThrowawayList { list in
          listID = list.id
          throw DeliberateFailure()
        }
      }
      let id = try #require(listID)
      #expect(try await !server.listIDs().contains(id))
    }
  }

  @Test func createsInANamedSource() async throws {
    try await ServerProcess.with { server in
      try await server.withThrowawayList { first in
        // Ask for the account the default-created list landed in, by name.
        try await server.withThrowawayList(sourceTitle: first.sourceTitle) { second in
          #expect(second.sourceTitle == first.sourceTitle)
        }
      }
    }
  }

  @Test func unknownSourceCreatesNothing() async throws {
    try await ServerProcess.with { server in
      let before = try await server.listIDs()
      let (text, isError) = try await server.client.callText(
        "create_list",
        [
          "title": .string(ServerProcess.throwawayPrefix + "unknown source"),
          "sourceTitle": "No Such Account \(UInt32.random(in: 0...UInt32.max))",
        ])
      #expect(isError)
      #expect(text.contains("Available sources"))
      #expect(try await server.listIDs() == before)
    }
  }

  @Test func mismatchedConfirmTitleKeepsTheList() async throws {
    try await ServerProcess.with { server in
      try await server.withThrowawayList { list in
        let (text, isError) = try await server.client.callText(
          "delete_list", ["id": .string(list.id), "confirmTitle": .string(list.title.lowercased())])
        #expect(isError)
        #expect(text.contains("not deleted"))
        #expect(try await server.listIDs().contains(list.id))
      }
    }
  }

  @Test func renamedListIsListedUnderItsNewTitle() async throws {
    try await ServerProcess.with { server in
      try await server.withThrowawayList { list in
        let newTitle = list.title + " renamed"
        let renamed = try await server.client.callDecoding(
          ListPayload.self, "rename_list", ["id": .string(list.id), "title": .string(newTitle)]
        ).list
        #expect(renamed.id == list.id)
        #expect(renamed.title == newTitle)
        let listed = try await server.client.callDecoding(ListsPayload.self, "list_lists").lists
        #expect(listed.first { $0.id == list.id }?.title == newTitle)
      }
    }
  }

  /// The harness must never delete a list that doesn't carry the throwaway prefix.
  @Test func teardownRefusesListsWithoutThePrefix() async throws {
    try await ServerProcess.with { server in
      var listID: String?
      await #expect(throws: HarnessError.self) {
        try await server.withThrowawayList { list in
          listID = list.id
          _ = try await server.client.callDecoding(
            ListPayload.self, "rename_list",
            ["id": .string(list.id), "title": .string("Harness guard check \(list.id)")])
        }
      }

      // Teardown refused, so the list survives; restore the prefix and remove it here.
      let id = try #require(listID)
      #expect(try await server.listIDs().contains(id))
      let restoredTitle = ServerProcess.throwawayPrefix + "harness guard"
      _ = try await server.client.callDecoding(
        ListPayload.self, "rename_list", ["id": .string(id), "title": .string(restoredTitle)])
      _ = try await server.client.callDecoding(
        DeletedListPayload.self, "delete_list",
        ["id": .string(id), "confirmTitle": .string(restoredTitle)])
      #expect(try await !server.listIDs().contains(id))
    }
  }

  @Test func deleteListIsHiddenWithoutTheFlag() async throws {
    let names = try await ServerProcess.with(arguments: []) { server in
      Set(try await server.client.listTools().tools.map(\.name))
    }
    #expect(names.contains("create_list"))
    #expect(!names.contains("delete_list"))
  }
}
