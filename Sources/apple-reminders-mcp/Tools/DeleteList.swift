import MCP
import RemindersCore

struct DeletedListResult: Codable, Sendable {
  var deleted: ReminderListDTO
}

enum DeleteList {
  private struct Input: Decodable {
    var id: String
    var confirmTitle: String
  }

  static let handler = ToolHandler(
    name: "delete_list",
    description: """
      Permanently delete an Apple Reminders list AND every reminder in it. This can't be \
      undone. confirmTitle must exactly match the list's current title (case-sensitive), \
      otherwise nothing is deleted. Confirm with the user before calling this.
      """,
    inputSchema: [
      "type": "object",
      "properties": [
        "id": ["type": "string", "description": "The list's id, from list_lists."],
        "confirmTitle": [
          "type": "string",
          "description": "The list's exact current title, as a safety check.",
        ],
      ],
      "required": ["id", "confirmTitle"],
      "additionalProperties": false,
    ],
    access: .delete,
    run: { arguments, store in
      let input = try arguments.decode(Input.self)
      return DeletedListResult(
        deleted: try await store.deleteList(id: input.id, confirmTitle: input.confirmTitle))
    }
  )
}
