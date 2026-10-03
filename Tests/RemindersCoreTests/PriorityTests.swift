import Testing

@testable import RemindersCore

@Suite struct PriorityTests {
  @Test(arguments: [
    (0, Priority.none), (1, .high), (2, .high), (3, .high), (4, .high), (5, .medium),
    (6, .low), (7, .low), (8, .low), (9, .low),
  ])
  func readsEveryEventKitValue(value: Int, expected: Priority) {
    #expect(Priority(eventKitValue: value) == expected)
  }

  @Test(arguments: [-1, 10, 100])
  func outOfRangeValuesAreNone(value: Int) {
    #expect(Priority(eventKitValue: value) == .none)
  }

  @Test(arguments: Priority.allCases)
  func roundTripsThroughEventKit(priority: Priority) {
    #expect(Priority(eventKitValue: priority.eventKitValue) == priority)
  }

  @Test func writesCanonicalEventKitValues() {
    #expect(Priority.allCases.map(\.eventKitValue) == [0, 9, 5, 1])
  }

  @Test func usesLowercaseNamesInJSON() {
    #expect(Priority.allCases.map(\.rawValue) == ["none", "low", "medium", "high"])
  }
}
