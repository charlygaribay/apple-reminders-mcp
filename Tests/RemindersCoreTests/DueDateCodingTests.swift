import Foundation
import Testing

@testable import RemindersCore

private let denver = TimeZone(identifier: "America/Denver")!
private let utc = TimeZone(identifier: "UTC")!

/// 2026-10-09 23:00:00 UTC (17:00 in Denver, which is on MDT, UTC-6, in October).
private let instant = Date(timeIntervalSince1970: 1_791_586_800)

@Suite struct DueDateParsingTests {
  @Test func dateOnly() throws {
    #expect(try DueDate(iso8601: "2026-10-09") == .date(year: 2026, month: 10, day: 9))
  }

  @Test(arguments: [
    "2026-10-09T17:00:00-06:00",
    "2026-10-09T17:00-06:00",
    "2026-10-09T17:00:00-0600",
    "2026-10-09T23:00:00Z",
    "2026-10-09T23:00:00.000Z",
    "2026-10-10T04:30:00+05:30",
  ])
  func dateTimeWithOffset(text: String) throws {
    #expect(try DueDate(iso8601: text, timeZone: utc) == .dateTime(instant))
  }

  @Test func dateTimeWithoutOffsetUsesTheGivenTimeZone() throws {
    #expect(try DueDate(iso8601: "2026-10-09T17:00:00", timeZone: denver) == .dateTime(instant))
    #expect(try DueDate(iso8601: "2026-10-09T17:00", timeZone: denver) == .dateTime(instant))
  }

  @Test func fractionalSecondsAreKept() throws {
    #expect(
      try DueDate(iso8601: "2026-10-09T23:00:00.5Z") == .dateTime(instant.addingTimeInterval(0.5)))
  }

  @Test(arguments: [
    "", " ", "tomorrow", "10/09/2026", "2026-10-9", "2026-13-01", "2026-00-10", "2026-02-30",
    "2026-10-09T25:00:00Z", "2026-10-09T17:60:00Z", "2026-10-09T17:00:00+25:00",
    "2026-10-09 17:00:00", "2026-10-09T17Z", " 2026-10-09",
  ])
  func invalidStringsNameTheBadValue(text: String) {
    #expect {
      try DueDate(iso8601: text, timeZone: utc)
    } throws: { error in
      guard case .invalidArgument(let message) = error as? RemindersError else { return false }
      return message.contains("'\(text)'")
    }
  }
}

@Suite struct DueDateFormattingTests {
  @Test func dateOnly() {
    #expect(DueDate.date(year: 2026, month: 3, day: 7).iso8601() == "2026-03-07")
  }

  @Test func dateTimeUsesTheGivenTimeZoneOffset() {
    #expect(DueDate.dateTime(instant).iso8601(timeZone: denver) == "2026-10-09T17:00:00-06:00")
    #expect(DueDate.dateTime(instant).iso8601(timeZone: utc) == "2026-10-09T23:00:00Z")
  }

  @Test(arguments: [
    DueDate.date(year: 2026, month: 12, day: 31),
    DueDate.date(year: 2028, month: 2, day: 29),
    DueDate.dateTime(instant),
  ])
  func roundTrips(dueDate: DueDate) throws {
    #expect(try DueDate(iso8601: dueDate.iso8601(timeZone: denver), timeZone: denver) == dueDate)
  }
}

@Suite struct DueDateComponentsTests {
  @Test func dateOnlyHasNoTimeOfDay() {
    let components = DueDate.date(year: 2026, month: 10, day: 9).dateComponents(timeZone: denver)
    #expect(components.year == 2026)
    #expect(components.month == 10)
    #expect(components.day == 9)
    #expect(components.hour == nil)
    #expect(components.minute == nil)
  }

  @Test func dateTimeCarriesTimeInTheGivenZone() {
    let components = DueDate.dateTime(instant).dateComponents(timeZone: denver)
    #expect(components.hour == 17)
    #expect(components.minute == 0)
    #expect(components.timeZone == denver)
  }

  @Test(arguments: [DueDate.date(year: 2026, month: 10, day: 9), DueDate.dateTime(instant)])
  func roundTripsThroughComponents(dueDate: DueDate) {
    #expect(
      DueDate(dateComponents: dueDate.dateComponents(timeZone: denver), timeZone: denver)
        == dueDate)
  }

  @Test func componentsWithoutTimeZoneUseTheGivenOne() {
    let components = DateComponents(year: 2026, month: 10, day: 9, hour: 17, minute: 0)
    #expect(DueDate(dateComponents: components, timeZone: denver) == .dateTime(instant))
  }

  @Test func incompleteComponentsAreNil() {
    #expect(DueDate(dateComponents: DateComponents(month: 10, day: 9), timeZone: utc) == nil)
  }
}

@Suite struct DueDateCodableTests {
  private struct Wrapper: Codable, Equatable {
    var dueDate: DueDate
  }

  @Test func encodesAsAString() throws {
    let json = try JSONEncoder().encode(Wrapper(dueDate: .date(year: 2026, month: 10, day: 9)))
    #expect(String(decoding: json, as: UTF8.self) == #"{"dueDate":"2026-10-09"}"#)
  }

  @Test func decodingAnInvalidStringFailsWithTheValue() {
    let json = Data(#"{"dueDate":"someday"}"#.utf8)
    #expect {
      try JSONDecoder().decode(Wrapper.self, from: json)
    } throws: { error in
      guard case .dataCorrupted(let context) = error as? DecodingError else { return false }
      return context.debugDescription.contains("'someday'")
    }
  }
}
