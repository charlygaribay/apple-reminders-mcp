import Testing

@testable import apple_reminders_mcp

@Suite struct ServerModeTests {
  @Test func defaultsToStandard() {
    #expect(ServerMode.resolve(allowDeleteFlag: false, environment: [:]) == .standard)
  }

  @Test func flagEnablesDeletes() {
    #expect(ServerMode.resolve(allowDeleteFlag: true, environment: [:]) == .allowDelete)
  }

  @Test func environmentEnablesDeletes() {
    let environment = ["REMINDERS_MCP_ALLOW_DELETE": "1"]
    #expect(ServerMode.resolve(allowDeleteFlag: false, environment: environment) == .allowDelete)
  }

  @Test(arguments: ["0", "", "true", "yes"])
  func onlyOneEnablesDeletesFromEnvironment(value: String) {
    let environment = ["REMINDERS_MCP_ALLOW_DELETE": value]
    #expect(ServerMode.resolve(allowDeleteFlag: false, environment: environment) == .standard)
  }
}
