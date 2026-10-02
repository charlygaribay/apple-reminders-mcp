import MCP
import RemindersCore

struct ListListsResult: Codable, Sendable {
  var lists: [ReminderListDTO]
}

enum ListLists {
  static let handler = ToolHandler(
    tool: Tool(
      name: "list_lists",
      description: """
        List all Apple Reminders lists with their id, title, account (sourceTitle), and number \
        of incomplete reminders. Use the returned ids to target other tools at a list.
        """,
      inputSchema: [
        "type": "object",
        "properties": [:],
        "additionalProperties": false,
      ],
      annotations: .init(readOnlyHint: true, openWorldHint: false)
    ),
    run: { _, store in
      ListListsResult(lists: try await store.listLists())
    }
  )
}
