import RemindersCore
import TestSupport
import Testing

private struct ListListsPayload: Decodable, Sendable {
  var lists: [ReminderListDTO]
}

@Suite(.enabled(if: integrationEnabled), .serialized)
struct ListListsEndToEndTests {
  @Test func returnsListsFromRealReminders() async throws {
    let server = try await ServerProcess.start()
    let lists: [ReminderListDTO]
    do {
      lists = try await server.client.callDecoding(ListListsPayload.self, "list_lists").lists
    } catch {
      await server.stop()
      throw error
    }
    await server.stop()

    // Reminders always has at least its default list; nothing else is assumed about user data.
    #expect(!lists.isEmpty)
    #expect(lists.allSatisfy { !$0.id.isEmpty })
  }
}
