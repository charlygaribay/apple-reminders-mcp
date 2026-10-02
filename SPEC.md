# Spec: Apple Reminders MCP Server

> Status: **Approved** · Author: Charly Garibay · Last updated: 2026-10-02

## Objective

Build a local [Model Context Protocol](https://modelcontextprotocol.io) server that lets an MCP client (Claude Code, Claude Desktop) read and manage Apple Reminders on this Mac through the native EventKit framework.

**User:** one person (the author) running it on their own Mac. The source is built locally and nothing is published or distributed.

**Why:** so an assistant can triage, capture, and clean up reminders in conversation ("what's due this week?", "add 'renew passport' to Personal for Friday") without AppleScript hacks or copying and pasting.

**Scope check (Phase 0):** this is one capability. It's a single server over a single data store (EventKit), and lists and reminders share the same store, permission, and tool layer. A capability map isn't needed.

### User stories / acceptance criteria

1. **Browse lists.** As a user, I can ask for my reminder lists and get each list's id, title, account/source, and incomplete count.
2. **Query reminders.** I can fetch reminders filtered by any combination of: list(s), status (`incomplete` default / `completed` / `all`), due-date range, overdue-only, completion-date range, and case-insensitive text match on title and notes. When `status` is `completed` or `all` and no completion-date range is given, completed reminders default to those completed in the **last 30 days**. Results are capped by `limit` (default 50, max 500), and the response says when results were truncated.
3. **Inspect one reminder.** I can fetch a single reminder by id with all of its v1 fields.
4. **Create a reminder.** I can create a reminder with a title (required) plus optional notes, due date (date-only or date-time), priority, URL, and target list. If no list is given, it goes to the default Reminders list.
5. **Update a reminder.** I can change any v1 field, including moving it to another list. To clear an optional field, I pass `null` for it. Fields I leave out stay unchanged.
6. **Complete / uncomplete.** I can mark a reminder completed or incomplete.
7. **Manage lists.** I can create a list (in the default source, or a named one), rename a list, and delete a list.
8. **Delete reminders.** I can delete a reminder by id.
9. **Safe by default.** `delete_reminder` and `delete_list` are only registered when the server starts with `--allow-delete` (or `REMINDERS_MCP_ALLOW_DELETE=1`). Without that flag they don't appear in `tools/list` at all. `delete_list` deletes the list and everything in it once `confirmTitle` matches. There's no separate `force` flag.
11. **Read-only mode.** Starting with `--read-only` (or `REMINDERS_MCP_READ_ONLY=1`) registers only `list_lists`, `list_reminders`, and `get_reminder`. Combining `--read-only` with `--allow-delete` is a startup error: the server exits non-zero with a message on stderr.
10. **Graceful permission handling.** If Reminders access is denied or hasn't been determined, every tool returns a clear MCP tool error that explains how to grant access in System Settings. The server never crashes or hangs.

### v1 reminder fields

| Field | Type (JSON) | EventKit mapping |
|---|---|---|
| `id` | string | `calendarItemIdentifier` |
| `title` | string | `title` |
| `notes` | string \| null | `notes` |
| `listId` / `listTitle` | string | `calendar.calendarIdentifier` / `.title` |
| `dueDate` | ISO 8601 string \| null. Date-only `2026-10-09`, or date-time `2026-10-09T17:00:00-06:00` | `dueDateComponents` (date-only → no time components) |
| `priority` | `"none" \| "low" \| "medium" \| "high"` | `priority` 0 / 9 / 5 / 1 |
| `url` | string \| null | `url` |
| `completed` | bool | `isCompleted` |
| `completedAt` | ISO 8601 \| null | `completionDate` |
| `createdAt` / `modifiedAt` | ISO 8601 \| null | `creationDate` / `lastModifiedDate` |

**Explicitly out of scope for v1:** recurrence rules, alarms/location triggers, subtasks, tags, sections, flags, attachments, and smart lists. Most of these aren't exposed by public EventKit APIs. Also out of scope: HTTP/SSE transport, multi-user use, and packaging (Homebrew, notarization).

### MCP tool surface

| Tool | Purpose | Gated |
|---|---|---|
| `list_lists` | All reminder lists, with incomplete counts | — (always) |
| `list_reminders` | Filtered query (see story 2) | — (always) |
| `get_reminder` | One reminder by id | — (always) |
| `create_reminder` | Create (story 4) | hidden in `--read-only` |
| `update_reminder` | Partial update / move (story 5) | hidden in `--read-only` |
| `set_reminder_completed` | `{ id, completed: bool }` | hidden in `--read-only` |
| `create_list` | `{ title, sourceTitle? }` | hidden in `--read-only` |
| `rename_list` | `{ id, title }` | hidden in `--read-only` |
| `delete_reminder` | `{ id }` | `--allow-delete` |
| `delete_list` | `{ id, confirmTitle }`. `confirmTitle` must exactly match the list's current title. Deletes the list and its reminders | `--allow-delete` |

Tool counts by mode: default = 8, `--allow-delete` = 10, `--read-only` = 3.

Every tool returns its result as JSON text content. Failures come back as MCP tool results with `isError: true` and a human-readable message, never as protocol errors or crashes. Read-only tools carry the `readOnlyHint` annotation, and delete tools carry `destructiveHint`.

## Tech Stack

- **Language:** Swift 6 (language mode 6, strict concurrency). The local toolchain is Swift 6.3.3.
- **Platform:** macOS 14+ (needed for `requestFullAccessToReminders()`). Developed on macOS 26.6.
- **Frameworks:** EventKit, Foundation.
- **Dependencies:**
  - [`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk) `from: "0.12.1"`: the official MCP SDK, used for the server and the stdio transport.
  - [`apple/swift-argument-parser`](https://github.com/apple/swift-argument-parser) `from: "1.5.0"`: CLI flags.
  - No other runtime dependencies without asking.
- **Build system:** Swift Package Manager. No Xcode project (only Command Line Tools are installed).
- **Transport:** stdio only.

## Commands

```bash
# Build (debug)
swift build

# Build (release binary at .build/release/apple-reminders-mcp)
swift build -c release

# Unit tests (no Reminders access needed; uses the in-memory fake store)
swift test

# Integration tests against real Reminders (uses a throwaway list "MCP Test <uuid>", cleaned up after)
REMINDERS_MCP_INTEGRATION=1 swift test --filter IntegrationTests

# Format check / fix (swift-format ships with the Swift 6 toolchain)
swift format lint --recursive --strict Sources Tests
swift format --in-place --recursive Sources Tests

# Run the server manually (speaks MCP over stdio)
.build/release/apple-reminders-mcp
.build/release/apple-reminders-mcp --allow-delete
.build/release/apple-reminders-mcp --read-only

# Interactive debugging with the MCP Inspector
npx @modelcontextprotocol/inspector .build/release/apple-reminders-mcp

# Install for personal use
mkdir -p ~/.local/bin && cp .build/release/apple-reminders-mcp ~/.local/bin/

# Register with Claude Code
claude mcp add apple-reminders -- ~/.local/bin/apple-reminders-mcp
```

## Project Structure

```
Package.swift                         → SwiftPM manifest: 3 targets + test targets
Sources/
  RemindersCore/                      → Pure domain layer, no MCP and no EventKit
    Models.swift                      → ReminderDTO, ReminderListDTO, Priority, DueDate, ReminderQuery, patch types
    RemindersStore.swift              → `protocol RemindersStore` (async, Sendable) + RemindersError
    DueDateCoding.swift               → ISO 8601 date-only / date-time parse + format
  RemindersEventKit/                  → The only target that imports EventKit
    EventKitStore.swift               → `RemindersStore` implementation over EKEventStore
    EventKitMapping.swift             → EKReminder ⇄ DTO, priority mapping, DateComponents handling
  apple-reminders-mcp/                → Executable target
    main.swift                        → ArgumentParser entry point; builds the store and starts the server
    ToolRegistry.swift                → Tool definitions (JSON Schemas), delete gating, dispatch
    Tools/*.swift                     → One file per tool: decode args → call store → encode result
    Info.plist                        → Embedded into the binary (NSRemindersFullAccessUsageDescription)
Tests/
  RemindersCoreTests/                 → Date coding, query/patch validation
  ServerTests/                        → Tool handlers against FakeRemindersStore (schemas, gating, errors)
  IntegrationTests/                   → EventKitStore against real Reminders, skipped unless env var set
  Support/FakeRemindersStore.swift    → In-memory store used by unit tests
README.md                             → Setup, permission grant, client registration
SPEC.md                               → This file
tasks/                                → plan.md, todo.md (created in the Plan phase)
```

Dependency direction: `apple-reminders-mcp` → `RemindersEventKit` → `RemindersCore`. `RemindersCore` imports only Foundation.

## Code Style

- Follow `swift format` defaults (2-space indent, 100-col lines). Use the Swift API Design Guidelines for naming.
- Put value types (`struct`, `enum`) in Core and make them `Sendable` + `Codable`. The EventKit store is an `actor`.
- Use `async throws` throughout. Throw typed `RemindersError` cases, and convert them to tool errors in exactly one place (the tool dispatcher).
- Don't use force unwraps (`!`) or `try!` in `Sources/`.
- Comments explain *why* (EventKit quirks especially), not *what*.
- **stdout belongs to the MCP protocol.** All logging goes to stderr via `FileHandle.standardError`, or uses `os.Logger`.

```swift
public enum RemindersError: Error, Equatable, Sendable {
  case accessDenied
  case notFound(kind: String, id: String)
  case invalidArgument(String)
  case readOnlyList(title: String)
}

public actor EventKitStore: RemindersStore {
  private let store = EKEventStore()

  public func setCompleted(id: String, completed: Bool) async throws -> ReminderDTO {
    try await ensureAccess()
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
      throw RemindersError.notFound(kind: "reminder", id: id)
    }
    reminder.isCompleted = completed
    // commit: true — callers expect the change to be durable once the tool returns.
    try store.save(reminder, commit: true)
    return ReminderDTO(reminder)
  }
}
```

## Testing Strategy

- **Framework:** Swift Testing (`import Testing`, `@Test`, `#expect`), which is bundled with the Swift 6 toolchain.
- **Unit (bulk of the coverage):**
  - `RemindersCoreTests`: due-date parsing and formatting (date-only vs date-time, time zones, invalid input), priority mapping, query validation (limit bounds, date range order), and patch semantics (absent vs `null`).
  - `ServerTests`: drive the tool handlers with `FakeRemindersStore`. Cover every tool's success path, argument validation errors, the `notFound` / `accessDenied` → `isError` mapping, the tool set for each mode (default 8 / `--allow-delete` 10 / `--read-only` 3), `--read-only` + `--allow-delete` rejected at startup, the 30-day default window for completed reminders, `delete_list` rejecting a mismatched `confirmTitle`, and truncation reporting.
- **Integration (opt-in):** `IntegrationTests` exercise `EventKitStore` against real Reminders. The suite only runs when `REMINDERS_MCP_INTEGRATION=1`. It creates a uniquely named throwaway list, does all its work inside that list, and deletes the list in teardown. **It never reads or modifies any other list.**
- **Manual smoke test:** before calling v1 done, run each tool once through MCP Inspector and once from Claude Code.
- **Coverage target:** every tool handler and every `RemindersError` path is covered by at least one unit test. There's no numeric % gate.
- **TDD:** write the failing test first for Core and Server logic. EventKit mapping is checked through integration tests.

## Boundaries

- **Always:**
  - Run `swift build` and `swift test` before declaring a task done.
  - Keep stdout clean for the protocol and log to stderr.
  - Validate tool arguments and return `isError` results instead of throwing out of handlers.
  - Keep EventKit confined to `RemindersEventKit`.
  - Make integration tests touch only their own throwaway list.
  - Update this spec when a decision changes.
- **Ask first:**
  - Adding any dependency beyond the two listed.
  - Changing the tool names or argument shapes after they're approved.
  - Raising the minimum macOS version.
  - Adding fields or features that are out of scope.
  - Running anything that writes to the user's **real** reminders, outside the throwaway integration-test list.
  - Changing the delete-gating or read-only behavior.
- **Never:**
  - Delete or modify the user's real reminders or lists during development or testing.
  - Expose delete tools without the opt-in flag.
  - Shell out to AppleScript/`osascript`.
  - Write anything except MCP frames to stdout.
  - Commit `.build/` or any personal reminder data (fixtures must be synthetic).

## Success Criteria

- [ ] `swift build -c release` produces `apple-reminders-mcp` with zero warnings under Swift 6 strict concurrency.
- [ ] `swift test` passes, and every tool plus every error path has a unit test.
- [ ] `REMINDERS_MCP_INTEGRATION=1 swift test --filter IntegrationTests` passes on this Mac and leaves no test list behind.
- [ ] MCP Inspector shows 8 tools by default, 10 with `--allow-delete`, and 3 with `--read-only`. Passing both flags exits non-zero.
- [ ] From Claude Code, stories 1–8 each complete successfully in a real conversation. The results show up in Reminders.app within a few seconds (and sync to iCloud).
- [ ] With Reminders access revoked in System Settings, every tool returns an `isError` result that names the fix, and the process stays alive.
- [ ] `list_reminders` on a store with ~1,000 reminders returns in under 2 s.
- [ ] README documents build, install, permission grant, and Claude Code registration.

## Risks / Known Unknowns

1. **TCC permission attribution for a CLI binary.** Under stdio, macOS attributes the Reminders prompt to the *responsible* process (the terminal or the Claude app), not to the binary itself. Without an embedded `Info.plist` containing `NSRemindersFullAccessUsageDescription`, the access request can fail silently. Mitigation: embed the plist with `-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist`, and verify the prompt early, as the first plan task.
2. **Swift Testing with Command Line Tools only (no Xcode).** This usually works with the Swift 6 toolchain, but it needs to be verified in task 1. Fallback: install Xcode, or use a minimal custom test runner.
3. **swift-sdk is pre-1.0 (0.12.x).** APIs may change, so pin to `.upToNextMinor(from: "0.12.1")`.
4. **Read-only / shared lists.** Some lists can't be modified (`allowsContentModifications == false`), so the store must surface `readOnlyList` instead of failing obscurely.

## Resolved Decisions

1. `delete_list` has no `force` flag. A matching `confirmTitle` is enough, and it deletes the list together with its reminders.
2. Completed reminders default to the last 30 days, unless the caller passes an explicit completion-date range.
3. A `--read-only` flag exposes only the 3 read tools, and it can't be combined with `--allow-delete`.
