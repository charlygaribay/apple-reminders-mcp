import MCP
import RemindersCore

enum RenameList {
  private struct Input: Decodable {
    var id: String
    var title: String
  }

  static let handler = ToolHandler(
    name: "rename_list",
    description: "Rename an Apple Reminders list. Returns the updated list.",
    inputSchema: [
      "type": "object",
      "properties": [
        "id": ["type": "string", "description": "The list's id, from list_lists."],
        "title": ["type": "string", "description": "The new name."],
      ],
      "required": ["id", "title"],
      "additionalProperties": false,
    ],
    access: .write,
    run: { arguments, store in
      let input = try arguments.decode(Input.self)
      return ListResult(
        list: try await store.renameList(id: input.id, title: try validatedTitle(input.title)))
    }
  )
}
