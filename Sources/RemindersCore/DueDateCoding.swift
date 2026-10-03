import Foundation

/// When a reminder is due: a whole day (shown as all-day in Reminders) or a specific instant.
public enum DueDate: Hashable, Sendable {
  case date(year: Int, month: Int, day: Int)
  case dateTime(Date)
}

// MARK: - ISO 8601 text

extension DueDate {
  /// Parses `YYYY-MM-DD`, or an ISO 8601 date-time `YYYY-MM-DDTHH:MM[:SS[.fff]]` followed by
  /// `Z`, `±HH:MM`, or `±HHMM`. A date-time without an offset is read in `timeZone`, since
  /// assistants often send local wall-clock times like "2026-10-09T17:00".
  public init(iso8601 text: String, timeZone: TimeZone = .current) throws {
    let pattern =
      /([0-9]{4})-([0-9]{2})-([0-9]{2})(?:T([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]{1,9}))?)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?/
    guard let match = text.wholeMatch(of: pattern) else { throw Self.invalid(text) }
    let (_, year, month, day, hour, minute, second, fraction, offset) = match.output
    func number(_ digits: Substring) throws -> Int {
      guard let value = Int(digits) else { throw Self.invalid(text) }
      return value
    }
    let ymd = (try number(year), try number(month), try number(day))

    guard let hour, let minute else {
      guard Self.isValidDay(ymd) else { throw Self.invalid(text) }
      self = .date(year: ymd.0, month: ymd.1, day: ymd.2)
      return
    }

    guard let zone = try offset.map({ try Self.timeZone(offset: $0, text: text) }) ?? timeZone
    else { throw Self.invalid(text) }
    let components = DateComponents(
      year: ymd.0, month: ymd.1, day: ymd.2,
      hour: try number(hour), minute: try number(minute),
      second: try second.map(number) ?? 0)
    guard let date = Self.validDate(components, in: zone) else { throw Self.invalid(text) }
    let fractionalSeconds = fraction.flatMap { Double("0.\($0)") } ?? 0
    self = .dateTime(date.addingTimeInterval(fractionalSeconds))
  }

  /// `YYYY-MM-DD` for a day, or an ISO 8601 date-time with `timeZone`'s offset (`Z` for UTC).
  public func iso8601(timeZone: TimeZone = .current) -> String {
    switch self {
    case .date(let year, let month, let day):
      return String(format: "%04d-%02d-%02d", year, month, day)
    case .dateTime(let date):
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = timeZone
      formatter.formatOptions = [.withInternetDateTime]
      if date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) != 0 {
        formatter.formatOptions.insert(.withFractionalSeconds)
      }
      return formatter.string(from: date)
    }
  }

  private static func invalid(_ text: String) -> RemindersError {
    .invalidArgument(
      "invalid date '\(text)': expected YYYY-MM-DD or an ISO 8601 date-time such as "
        + "2026-10-09T17:00:00-06:00")
  }

  /// `Z`, `±HH:MM`, or `±HHMM`, within the ±14:00 range real time zones use.
  private static func timeZone(offset: Substring, text: String) throws -> TimeZone? {
    if offset == "Z" { return .gmt }
    let digits = offset.dropFirst().filter(\.isNumber)
    guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)),
      hours <= 14, minutes < 60
    else { throw invalid(text) }
    let seconds = (hours * 3600 + minutes * 60) * (offset.first == "-" ? -1 : 1)
    return TimeZone(secondsFromGMT: seconds)
  }

  private static func isValidDay(_ ymd: (Int, Int, Int)) -> Bool {
    let components = DateComponents(year: ymd.0, month: ymd.1, day: ymd.2)
    return validDate(components, in: .gmt) != nil
  }

  /// The date for `components`, or nil if they don't name a real moment (Feb 30, 25:00, a
  /// skipped DST hour): Calendar silently rolls those over, so check nothing moved.
  private static func validDate(_ components: DateComponents, in zone: TimeZone) -> Date? {
    let calendar = gregorian(zone)
    guard let date = calendar.date(from: components) else { return nil }
    let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let fields: [KeyPath<DateComponents, Int?>] = [
      \.year, \.month, \.day, \.hour, \.minute, \.second,
    ]
    let unchanged = fields.allSatisfy {
      components[keyPath: $0] == nil || components[keyPath: $0] == back[keyPath: $0]
    }
    return unchanged ? date : nil
  }

  fileprivate static func gregorian(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }
}

// MARK: - DateComponents (EventKit's dueDateComponents)

extension DueDate {
  /// Day-only components for `.date`, so Reminders shows the reminder as all-day.
  public func dateComponents(timeZone: TimeZone = .current) -> DateComponents {
    switch self {
    case .date(let year, let month, let day):
      return DateComponents(year: year, month: month, day: day)
    case .dateTime(let date):
      let calendar = Self.gregorian(timeZone)
      var components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: date)
      components.calendar = calendar
      components.timeZone = timeZone
      return components
    }
  }

  /// Components without an hour are a day; otherwise an instant, read in the components' own
  /// time zone or else `timeZone`. Nil when year, month, or day is missing.
  public init?(dateComponents components: DateComponents, timeZone: TimeZone = .current) {
    guard let year = components.year, let month = components.month, let day = components.day
    else { return nil }
    guard let hour = components.hour else {
      self = .date(year: year, month: month, day: day)
      return
    }
    let calendar = Self.gregorian(components.timeZone ?? timeZone)
    let resolved = DateComponents(
      year: year, month: month, day: day,
      hour: hour, minute: components.minute ?? 0, second: components.second ?? 0)
    guard let date = calendar.date(from: resolved) else { return nil }
    self = .dateTime(date)
  }
}

// MARK: - Codable, as the ISO 8601 string

extension DueDate: Codable {
  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    do {
      try self.init(iso8601: text)
    } catch let error as RemindersError {
      guard case .invalidArgument(let message) = error else { throw error }
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: message))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(iso8601())
  }
}
