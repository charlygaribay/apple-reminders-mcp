import Testing

@testable import RemindersCore

@Suite struct ValidationTests {
  @Test func trimsSurroundingWhitespace() throws {
    #expect(try validatedTitle("  Groceries\n") == "Groceries")
  }

  @Test func keepsInnerWhitespace() throws {
    #expect(try validatedTitle("Home  Depot") == "Home  Depot")
  }

  @Test func blankTitleNamesTheField() {
    #expect(throws: RemindersError.invalidArgument("'newTitle' must not be empty")) {
      try validatedTitle(" ", field: "newTitle")
    }
  }
}
