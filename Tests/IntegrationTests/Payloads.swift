import RemindersCore

// Tool result shapes, decoded independently of the server's own types so the tests
// check the JSON contract rather than sharing code with the implementation.

struct ListsPayload: Decodable, Sendable {
  var lists: [ReminderListDTO]
}

struct ListPayload: Decodable, Sendable {
  var list: ReminderListDTO
}

struct DeletedListPayload: Decodable, Sendable {
  var deleted: ReminderListDTO
}
