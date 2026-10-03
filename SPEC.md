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
- **Two binaries:** `apple-reminders-mcp` (the server) and `apple-reminders-mcp-launch` (what MCP clients run). The launcher re-execs the server in place with the private `responsibility_spawnattrs_setdisclaim` spawn attribute, which it looks up at runtime. That makes the server its own TCC-responsible process. The private API lives only in the launcher (see Resolved Decisions 4).
- **Code signing:** `scripts/build.sh` signs both binaries with a stable identity (default: a self-signed `apple-reminders-mcp dev` certificate in the login keychain), so the Reminders grant survives rebuilds.

## Commands

```bash
# Build + sign (debug). scripts/build.sh wraps `swift build`, forwarding all arguments,
# then signs both binaries so the Reminders grant survives rebuilds.
scripts/build.sh

# Build + sign (release binaries in .build/release/)
scripts/build.sh -c release

# Unit tests (no Reminders access needed; uses the in-memory fake store).
# scripts/test.sh wraps `swift test`, adding the Swift Testing search paths when only
# Command Line Tools are installed. All `swift test` arguments pass through.
scripts/test.sh

# Integration tests: run the built launcher + server over stdio against real Reminders.
# Builds and signs first. Writes happen only in a throwaway list "MCP Test <uuid>", deleted after.
REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests

# Format check / fix (swift-format ships with the Swift 6 toolchain)
swift format lint --recursive --strict Sources Tests
swift format --in-place --recursive Sources Tests

# Run the server manually (speaks MCP over stdio). Always go through the launcher.
.build/release/apple-reminders-mcp-launch
.build/release/apple-reminders-mcp-launch --allow-delete
.build/release/apple-reminders-mcp-launch --read-only

# Interactive debugging with the MCP Inspector
npx @modelcontextprotocol/inspector .build/release/apple-reminders-mcp-launch

# Install for personal use (both binaries must sit in the same directory)
mkdir -p ~/.local/bin && cp .build/release/apple-reminders-mcp .build/release/apple-reminders-mcp-launch ~/.local/bin/

# Register with Claude Code (register the launcher, not the server)
claude mcp add apple-reminders -- ~/.local/bin/apple-reminders-mcp-launch
```

## Project Structure

```
Package.swift                         → SwiftPM manifest: 4 targets + test targets
Sources/
  RemindersCore/                      → Pure domain layer, no MCP and no EventKit
    Models.swift                      → ReminderDTO, ReminderListDTO, Priority, DueDate, ReminderQuery, patch types
    RemindersStore.swift              → `protocol RemindersStore` (async, Sendable) + RemindersError
    DueDateCoding.swift               → ISO 8601 date-only / date-time parse + format
  RemindersEventKit/                  → The only target that imports EventKit
    EventKitStore.swift               → `RemindersStore` implementation over EKEventStore
    EventKitMapping.swift             → EKReminder ⇄ DTO, priority mapping, DateComponents handling
  apple-reminders-mcp/                → Executable target
    AppleRemindersMCP.swift           → @main ArgumentParser entry point; builds the store and starts the server
    ToolRegistry.swift                → Tool definitions (JSON Schemas), delete gating, dispatch
    Tools/*.swift                     → One file per tool: decode args → call store → encode result
    Info.plist                        → Embedded into the binary (NSRemindersFullAccessUsageDescription)
  apple-reminders-mcp-launch/         → Launcher executable (the only code using private API)
    Launcher.swift                    → Re-execs the sibling server as its own TCC-responsible process
Tests/
  RemindersCoreTests/                 → Date coding, query/patch validation
  ServerTests/                        → Tool handlers against FakeRemindersStore (schemas, gating, errors)
  LauncherTests/                      → Launcher path resolution
  IntegrationTests/                   → Built launcher + server over stdio, against real Reminders (opt-in)
  Support/                            → FakeRemindersStore + MCP client helpers shared by test targets
scripts/build.sh                      → `swift build` wrapper that signs both binaries (via sign.sh)
scripts/sign.sh                       → Signs launcher + server with the stable identity
scripts/test.sh                       → `swift test` wrapper (Swift Testing paths under Command Line Tools)
README.md                             → Setup, permission grant, client registration
SPEC.md                               → This file
tasks/                                → plan.md, todo.md (created in the Plan phase)
```

Dependency direction: `apple-reminders-mcp` → `RemindersEventKit` → `RemindersCore`. `RemindersCore` imports only Foundation. `apple-reminders-mcp-launch` depends on nothing in the package. It finds the server by path at runtime.

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
- **Integration (opt-in, end to end):** `IntegrationTests` start the built `apple-reminders-mcp-launch` as a child process and talk to it with the SDK's MCP client over stdio, which is exactly what real clients do. The suite only runs when `REMINDERS_MCP_INTEGRATION=1`.
  - **Why not in-process:** the test runner can't use EventKit itself. macOS attributes its requests to the app that launched it (Claude Code, Terminal), and none of those declare Reminders usage, so access is refused. Only the server binary, which goes through the launcher, holds the grant.
  - **Throwaway-list harness:** each test that writes creates a uniquely named list through `create_list`, works only inside it, and deletes it through `delete_list` (the server runs with `--allow-delete`). Tests may read other lists (e.g. `list_lists` returns everything), but they only assert on their own list, and they **never modify or print other lists' contents.**
  - **Before the harness exists** (until `create_list` and `delete_list` land), the only end-to-end test is the read-only `list_lists` one.
- **Manual smoke test:** before calling v1 done, run each tool once through MCP Inspector and once from Claude Code.
- **Coverage target:** every tool handler and every `RemindersError` path is covered by at least one unit test. There's no numeric % gate.
- **TDD:** write the failing test first for Core and Server logic. EventKit mapping is checked through the end-to-end integration tests.

## Boundaries

- **Always:**
  - Run `swift build` and `scripts/test.sh` before declaring a task done.
  - Keep stdout clean for the protocol and log to stderr.
  - Validate tool arguments and return `isError` results instead of throwing out of handlers.
  - Keep EventKit confined to `RemindersEventKit`, and private API confined to the launcher.
  - Build through `scripts/build.sh` so binaries keep a stable signature.
  - Make integration tests touch only their own throwaway list.
  - Update this spec when a decision changes.
- **Ask first:**
  - Adding any dependency beyond the two listed.
  - Changing the tool names or argument shapes after they're approved.
  - Raising the minimum macOS version.
  - Adding fields or features that are out of scope.
  - Running anything that writes to the user's **real** reminders, outside the throwaway integration-test list.
  - Changing the delete-gating or read-only behavior.
  - Using any other private or underscored API.
  - Touching the user's keychain, certificates, or TCC/privacy settings. Tell the user what to do instead.
- **Never:**
  - Delete or modify the user's real reminders or lists during development or testing.
  - Expose delete tools without the opt-in flag.
  - Shell out to AppleScript/`osascript`.
  - Write anything except MCP frames to stdout.
  - Commit `.build/` or any personal reminder data (fixtures must be synthetic).

## Success Criteria

- [ ] `scripts/build.sh -c release` produces both binaries, signed with the stable identity, with zero warnings under Swift 6 strict concurrency.
- [ ] `scripts/test.sh` passes, and every tool plus every error path has a unit test.
- [ ] `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests` passes on this Mac and leaves no test list behind.
- [ ] Through the launcher, MCP Inspector shows 8 tools by default, 10 with `--allow-delete`, and 3 with `--read-only`. Passing both flags exits non-zero.
- [ ] From Claude Code, stories 1–8 each complete successfully in a real conversation. The results show up in Reminders.app within a few seconds (and sync to iCloud).
- [ ] With Reminders access revoked in System Settings, every tool returns an `isError` result that names the fix, and the process stays alive.
- [ ] `list_reminders` on a store with ~1,000 reminders returns in under 2 s.
- [ ] Rebuilding and reinstalling doesn't trigger a new Reminders prompt.
- [ ] README documents certificate setup, build, install, permission grant, and Claude Code registration (via the launcher).

## Risks / Known Unknowns

1. ~~**TCC permission attribution for a CLI binary.**~~ **Resolved in task 3.** macOS attributes the request to the responsible process: the MCP client, e.g. `com.anthropic.claude-code`. TCC then refuses access *without prompting*, because that app has no `NSRemindersUsageDescription` (Terminal, Claude, and VS Code don't either). The embedded plist alone doesn't help. Fix: the launcher (Resolved Decisions 4). Remaining risk: Apple could change the private spawn attribute. If the lookup fails, the launcher warns on stderr and execs normally, and the server then reports `accessDenied`.
5. **TCC grant tied to the code signature.** Found in task 3: ad-hoc signatures change on every build, so the grant was lost after each rebuild and macOS re-prompted. Fixed by stable signing (Resolved Decisions 5). One trap: `swift test` relinks the executables whenever its flags differ from the last build, which silently restores ad-hoc signatures. `scripts/test.sh` therefore builds, signs, and then runs `swift test --skip-build`. The grant is also per binary path, so the installed copy gets its own one-time prompt. Verified 2026-10-03: two rebuilds with different content kept the grant.
2. ~~**Swift Testing with Command Line Tools only.**~~ **Resolved in task 1:** CLT ships `Testing.framework`, but SwiftPM doesn't search it. `scripts/test.sh` adds the `-F`/rpath flags when CLT is the active developer dir.
3. **swift-sdk is pre-1.0 (0.12.x).** APIs may change, so pin to `.upToNextMinor(from: "0.12.1")`.
4. **Read-only / shared lists.** Some lists can't be modified (`allowsContentModifications == false`), so the store must surface `readOnlyList` instead of failing obscurely.

## Resolved Decisions

1. `delete_list` has no `force` flag. A matching `confirmTitle` is enough, and it deletes the list together with its reminders.
2. Completed reminders default to the last 30 days, unless the caller passes an explicit completion-date range.
3. A `--read-only` flag exposes only the 3 read tools, and it can't be combined with `--allow-delete`.
4. **Launcher for TCC attribution.** MCP clients run `apple-reminders-mcp-launch`, which re-execs the sibling `apple-reminders-mcp` as its own responsible process. That way macOS prompts for the server, using its embedded Info.plist. The private spawn API is confined to the launcher, so the server itself uses only public API.
5. **Stable code signing.** A self-signed `apple-reminders-mcp dev` code-signing certificate, which the user creates once in Keychain Access, signs both binaries in `scripts/build.sh`, so the Reminders grant persists across rebuilds and upgrades.
6. **End-to-end integration tests.** Integration tests drive the real launcher and server over stdio, and the throwaway-list harness uses `create_list` and `delete_list`. List management and delete gating therefore move up in the plan, right after task 3.
