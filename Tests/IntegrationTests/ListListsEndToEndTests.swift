import RemindersCore
import TestSupport
import Testing

@Suite(.enabled(if: integrationEnabled), .serialized)
struct ListListsEndToEndTests {
  @Test func returnsListsFromRealReminders() async throws {
    let lists = try await ServerProcess.with(arguments: []) { server in
      try await server.client.callDecoding(ListsPayload.self, "list_lists").lists
    }
    // Reminders always has at least its default list; nothing else is assumed about user data.
    #expect(!lists.isEmpty)
    #expect(lists.allSatisfy { !$0.id.isEmpty })
  }
}
