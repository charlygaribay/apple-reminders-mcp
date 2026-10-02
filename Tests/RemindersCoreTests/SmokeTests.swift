import Testing

@testable import RemindersCore

@Test func serverIdentityIsSet() {
  #expect(RemindersCore.serverName == "apple-reminders-mcp")
  #expect(!RemindersCore.serverVersion.isEmpty)
}
