import Foundation

/// Trims surrounding whitespace and rejects titles that are empty afterwards.
public func validatedTitle(_ raw: String, field: String = "title") throws -> String {
  let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !title.isEmpty else {
    throw RemindersError.invalidArgument("'\(field)' must not be empty")
  }
  return title
}
