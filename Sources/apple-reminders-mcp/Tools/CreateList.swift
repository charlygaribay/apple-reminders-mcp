import MCP
import RemindersCore

/// A tool result carrying one list.
struct ListResult: Codable, Sendable {
  var list: ReminderListDTO
}

enum CreateList {
  private struct Input: Decodable {
    var title: String
    var sourceTitle: String?
  }

  static let handler = ToolHandler(
    name: "create_list",
    description: """
      Create a new Apple Reminders list. It goes in the default account unless sourceTitle \
      names another account (see sourceTitle values from list_lists). Returns the new list.
      """,
    inputSchema: [
      "type": "object",
      "properties": [
        "title": ["type": "string", "description": "Name of the new list."],
        "sourceTitle": [
          "type": "string",
          "description":
            "Account to create the list in, e.g. \"iCloud\". Defaults to the default account.",
        ],
      ],
      "required": ["title"],
      "additionalProperties": false,
    ],
    access: .write,
    run: { arguments, store in
      let input = try arguments.decode(Input.self)
      let list = try await store.createList(
        title: try validatedTitle(input.title), sourceTitle: input.sourceTitle)
      return ListResult(list: list)
    }
  )
}
