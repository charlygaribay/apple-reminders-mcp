import Testing

@testable import RemindersCore

@Suite struct RemindersErrorTests {
  @Test func accessDeniedPointsToSystemSettings() {
    let message = RemindersError.accessDenied.message
    #expect(message.contains("System Settings → Privacy & Security → Reminders"))
    #expect(message.contains("apple-reminders-mcp-launch"))
  }

  @Test func notFoundNamesKindAndId() {
    #expect(RemindersError.notFound(kind: "reminder", id: "X1").message == "reminder not found: X1")
  }

  @Test func readOnlyListNamesTheList() {
    #expect(RemindersError.readOnlyList(title: "Shared").message.contains("'Shared'"))
  }
}
