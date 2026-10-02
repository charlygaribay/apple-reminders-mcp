# Tasks: Apple Reminders MCP Server

> Plan: [plan.md](plan.md) · Spec: [SPEC.md](../SPEC.md)
> Standing verification for every task: `swift build` (zero warnings) and `scripts/test.sh` pass.

## Phase 1: Foundation & de-risking

### Task 1: Package skeleton, test harness, and a server that boots over stdio

**Description:** Create `Package.swift` with the three targets plus test targets, add the `swift-sdk` and `swift-argument-parser` dependencies, and write an `@main` `AppleRemindersMCP.swift` that starts an MCP `Server` over `StdioTransport` with zero tools. Add one trivial Swift Testing test to prove the harness works under Command Line Tools.

**Acceptance criteria:**
- [x] `swift build` resolves dependencies and builds `apple-reminders-mcp` under Swift 6 language mode.
- [x] `scripts/test.sh` runs at least one `@Test` successfully without Xcode installed.
- [x] MCP Inspector connects, completes `initialize`, and shows the server name and version. Nothing but MCP frames goes to stdout. *(Verified with a scripted JSON-RPC handshake over stdio. The interactive Inspector check is left for you.)*

**Verification:**
- [x] `swift build && scripts/test.sh`
- [ ] `npx @modelcontextprotocol/inspector .build/debug/apple-reminders-mcp`, which connects successfully

**Dependencies:** None
**Files:** `Package.swift`, `Sources/apple-reminders-mcp/AppleRemindersMCP.swift`, `Sources/RemindersCore/Models.swift` (placeholder), `Sources/RemindersEventKit/EventKitStore.swift` (placeholder), `Tests/RemindersCoreTests/SmokeTests.swift`
**Scope:** M

### Task 2: Core store protocol, tool registry, and `list_lists` against the fake store

**Description:** Define `ReminderListDTO`, `RemindersError`, and the `RemindersStore` protocol (starting with only `listLists()`). Build `ToolRegistry`: tool definitions with JSON Schemas and annotations, a dispatcher, and the single error → `isError` mapping. Implement the `list_lists` tool and an in-memory `FakeRemindersStore`.

**Acceptance criteria:**
- [x] `tools/list` returns `list_lists` with `readOnlyHint: true`.
- [x] Calling `list_lists` against the fake returns JSON that has each list's id, title, source title, and incomplete count.
- [x] A store that throws `accessDenied` produces an `isError` result whose message mentions System Settings → Privacy & Security → Reminders. An unknown tool name also produces `isError`.

**Verification:**
- [x] `scripts/test.sh --filter ServerTests`

**Dependencies:** 1
**Files:** `Sources/RemindersCore/Models.swift`, `Sources/RemindersCore/RemindersStore.swift`, `Sources/apple-reminders-mcp/ToolRegistry.swift`, `Sources/apple-reminders-mcp/Tools/ListLists.swift`, `Tests/Support/FakeRemindersStore.swift`, `Tests/ServerTests/ListListsTests.swift`
**Scope:** M

### Task 3: `EventKitStore` with permission handling and a real `list_lists`

**Description:** Implement the `EventKitStore` actor: `ensureAccess()` using `requestFullAccessToReminders()`, plus `listLists()` over `calendars(for: .reminder)`. Embed `Info.plist` through linker flags, then wire the real store into the entry point. Add the integration-test harness, which is gated on `REMINDERS_MCP_INTEGRATION=1` and creates and tears down a throwaway list.

**Acceptance criteria:**
- [ ] On first run from Claude Code, macOS shows the Reminders permission prompt (or access is already granted), and `list_lists` returns the real lists.
- [ ] `otool -s __TEXT __info_plist` on the binary shows the embedded usage description.
- [ ] The integration test creates a `MCP Test <uuid>` list, sees it in `listLists()`, deletes it, and leaves nothing behind.

**Verification:**
- [ ] `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests`
- [ ] Manual: `claude mcp add apple-reminders-dev -- $(pwd)/.build/debug/apple-reminders-mcp`, then ask "list my reminder lists"

**Dependencies:** 2
**Files:** `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/RemindersEventKit/EventKitMapping.swift`, `Sources/apple-reminders-mcp/Info.plist`, `Package.swift`, `Tests/IntegrationTests/EventKitStoreTests.swift`
**Scope:** M

## Checkpoint 1: Foundation
- [ ] All tests pass and the build is clean.
- [ ] `list_lists` returns real data from Claude Code.
- [ ] Record in SPEC.md which app ended up holding the Reminders permission.
- [ ] **Review with the human before proceeding.**

## Phase 2: Read path

### Task 4: Due-date coding and priority mapping in Core

**Description:** Add the `DueDate` enum with ISO 8601 parsing and formatting (date-only `YYYY-MM-DD`, and date-time with an offset or `Z`), conversion to and from `DateComponents`, and the `Priority` enum with EventKit integer mapping (0/9/5/1, with 1–4 → high, 5 → medium, 6–9 → low on read).

**Acceptance criteria:**
- [ ] Round-trip tests pass for date-only, date-time with an offset, and UTC `Z`. Invalid strings throw `invalidArgument` with the bad value in the message.
- [ ] Date-only produces `DateComponents` with no hour or minute.
- [ ] Every EventKit priority value 0–9 maps to the right `Priority`, and back.

**Verification:**
- [ ] `scripts/test.sh --filter RemindersCoreTests`

**Dependencies:** 1
**Files:** `Sources/RemindersCore/DueDateCoding.swift`, `Sources/RemindersCore/Models.swift`, `Tests/RemindersCoreTests/DueDateCodingTests.swift`, `Tests/RemindersCoreTests/PriorityTests.swift`
**Scope:** S

### Task 5: `get_reminder` end to end

**Description:** Add `ReminderDTO` with all v1 fields, `getReminder(id:)` in the protocol, fake, and EventKit store, the EKReminder → DTO mapping, and the `get_reminder` tool.

**Acceptance criteria:**
- [ ] `get_reminder` returns every field in the SPEC field table, with ISO 8601 dates and string priority.
- [ ] An unknown id produces an `isError` "reminder not found: <id>".
- [ ] An integration test creates a reminder directly through EventKit in the throwaway list and reads it back through the store with matching fields.

**Verification:**
- [ ] `scripts/test.sh --filter ServerTests` and `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests`

**Dependencies:** 3, 4
**Files:** `Sources/RemindersCore/Models.swift`, `Sources/RemindersEventKit/EventKitMapping.swift`, `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/GetReminder.swift`, `Tests/ServerTests/GetReminderTests.swift`
**Scope:** M

### Task 6: `list_reminders` with filters, the 30-day completed default, and truncation

**Description:** Add a `ReminderQuery` in Core with validation: limit 1–500 (default 50), range order, and status. Add a shared in-memory filter covering text, overdue, and limit/truncation. On the EventKit side, use predicates (incomplete by due range, completed by completion range, defaulting to the last 30 days) scoped to the requested lists. Implement the `list_reminders` tool, which returns `{ reminders, truncated, totalMatched }`.

**Acceptance criteria:**
- [ ] Each filter (lists, status, due range, overdue, completion range, text) has a passing test against the fake, both alone and in combination.
- [ ] `status: completed` with no completion range excludes a reminder completed 31 days ago and includes one completed 29 days ago.
- [ ] `limit` 0 or 501 produces `isError`. More matches than `limit` sets `truncated: true` with the correct `totalMatched`.

**Verification:**
- [ ] `scripts/test.sh` and the integration test for the EventKit predicate path
- [ ] Manual: ask Claude "what's due this week?"

**Dependencies:** 5
**Files:** `Sources/RemindersCore/ReminderQuery.swift`, `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/ListReminders.swift`, `Tests/RemindersCoreTests/ReminderQueryTests.swift`, `Tests/ServerTests/ListRemindersTests.swift`
**Scope:** M

## Checkpoint 2: Read path
- [ ] All tests pass.
- [ ] The 3 read tools work against real data from Claude Code.

## Phase 3: Write path

### Task 7: `create_reminder` end to end

**Description:** Add a `NewReminder` input with validation (non-empty title, valid URL), and `createReminder` in the protocol, fake, and EventKit store. The default list is `defaultCalendarForNewReminders()`. A read-only list throws `readOnlyList`. Implement the `create_reminder` tool, which returns the created DTO.

**Acceptance criteria:**
- [ ] Creating with only a title lands in the default list. Creating with all fields round-trips through `get_reminder`.
- [ ] An empty or whitespace title, an invalid date, an unknown `listId`, or a read-only list each produce a specific `isError`.
- [ ] An integration test creates a reminder in the throwaway list and verifies it through EventKit.

**Verification:**
- [ ] `scripts/test.sh` and `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests`

**Dependencies:** 5
**Files:** `Sources/RemindersCore/Models.swift`, `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/CreateReminder.swift`, `Tests/ServerTests/CreateReminderTests.swift`, `Tests/IntegrationTests/EventKitStoreTests.swift`
**Scope:** M

### Task 8: `update_reminder` (partial patch and move) and `set_reminder_completed`

**Description:** Add `FieldPatch<T>` tri-state decoding and a `ReminderPatch`. Implement `updateReminder` (including a `listId` move) and `setCompleted` in the protocol, fake, and EventKit store, plus both tools.

**Acceptance criteria:**
- [ ] An absent field stays unchanged, `null` clears it (notes, dueDate, url, priority → none), and a value sets it. `title: null` produces `isError`.
- [ ] Moving to another list via `listId` works. Moving to a read-only or unknown list produces `isError`.
- [ ] `set_reminder_completed` toggles both ways and sets or clears `completedAt`.

**Verification:**
- [ ] `scripts/test.sh` and the integration tests for patch and move within the throwaway list (plus a second throwaway list for the move)

**Dependencies:** 7
**Files:** `Sources/RemindersCore/FieldPatch.swift`, `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/UpdateReminder.swift`, `Sources/apple-reminders-mcp/Tools/SetReminderCompleted.swift`, `Tests/ServerTests/UpdateReminderTests.swift`
**Scope:** M

### Task 9: `create_list` and `rename_list`

**Description:** Add `createList(title:sourceTitle:)`, which uses the default reminders source unless `sourceTitle` names one (unknown → `isError` listing the available sources), and `renameList(id:title:)`. Implement both tools.

**Acceptance criteria:**
- [ ] `create_list` without a source uses the default source. With an unknown `sourceTitle`, it errors and names the valid sources.
- [ ] `rename_list` changes the title. An empty title or an immutable list produces `isError`.
- [ ] The integration test harness itself now uses `createList` for its throwaway list.

**Verification:**
- [ ] `scripts/test.sh` and `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests`

**Dependencies:** 3
**Files:** `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/CreateList.swift`, `Sources/apple-reminders-mcp/Tools/RenameList.swift`, `Tests/ServerTests/ListManagementTests.swift`, `Tests/IntegrationTests/EventKitStoreTests.swift`
**Scope:** M

## Checkpoint 3: Write path
- [ ] All tests pass and the integration run leaves no `MCP Test` lists behind.
- [ ] Stories 1–7 work from Claude Code.
- [ ] **Review with the human before proceeding.**

## Phase 4: Modes & destructive tools

### Task 10: Server modes (`--read-only`, `--allow-delete`, env vars, conflict check)

**Description:** Add ArgumentParser flags plus the `REMINDERS_MCP_READ_ONLY` and `REMINDERS_MCP_ALLOW_DELETE` env vars → `ServerMode`. Add `ToolRegistry.tools(for:)` filtering, plus a dispatcher guard that rejects tools not available in the current mode.

**Acceptance criteria:**
- [ ] The default mode lists 8 tools and read-only lists 3. (Allow-delete lists 8 until task 11.)
- [ ] `--read-only --allow-delete`, by flag or env var, exits non-zero with a stderr message before serving.
- [ ] In read-only mode, calling `create_reminder` by name produces `isError` "not available in read-only mode".

**Verification:**
- [ ] `scripts/test.sh --filter ServerModeTests`
- [ ] `.build/debug/apple-reminders-mcp --read-only --allow-delete; echo $?` prints non-zero

**Dependencies:** 8, 9
**Files:** `Sources/apple-reminders-mcp/AppleRemindersMCP.swift`, `Sources/apple-reminders-mcp/ServerMode.swift`, `Sources/apple-reminders-mcp/ToolRegistry.swift`, `Tests/ServerTests/ServerModeTests.swift`
**Scope:** S

### Task 11: `delete_reminder` and `delete_list` (gated, with `confirmTitle`)

**Description:** Add `deleteReminder(id:)` and `deleteList(id:confirmTitle:)` (which removes the list and its reminders) in the protocol, fake, and EventKit store. Register both tools only under `.allowDelete`, with `destructiveHint: true`.

**Acceptance criteria:**
- [ ] With `--allow-delete`, 10 tools are listed. Without it, the delete tools are absent and calling them by name produces `isError`.
- [ ] `delete_list` with a mismatched `confirmTitle` produces `isError` and the list survives. A matching title deletes it.
- [ ] Integration: delete a reminder, then the throwaway list itself, through the tools' store paths.

**Verification:**
- [ ] `scripts/test.sh` and `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests`

**Dependencies:** 10
**Files:** `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/DeleteReminder.swift`, `Sources/apple-reminders-mcp/Tools/DeleteList.swift`, `Tests/ServerTests/DeleteTests.swift`
**Scope:** M

## Checkpoint 4: Modes
- [ ] Inspector shows 8 / 10 / 3 tools by mode, and passing both flags exits non-zero.

## Phase 5: Hardening & docs

### Task 12: Access-denied UX check and performance check

**Description:** Revoke Reminders access and confirm every tool returns the guidance error with the process still alive (restore access afterwards). Add a read-only timing check that runs `list_reminders` with `status: all` across the real store.

**Acceptance criteria:**
- [ ] With access revoked, all 10 tools return `isError` with the System Settings path, and the server keeps responding.
- [ ] `list_reminders` across ~1,000 reminders finishes in < 2 s. Record the measured time in SPEC.md.

**Verification:**
- [ ] Manual, through Inspector. The timing is printed by an integration test that only reads.

**Dependencies:** 11
**Files:** `Tests/IntegrationTests/PerformanceTests.swift`, `SPEC.md`
**Scope:** S

### Task 13: README, install, and the final manual smoke test

**Description:** Write a README covering prerequisites, build, install to `~/.local/bin`, the permission grant (including which app holds it), Claude Code and Claude Desktop registration, the mode flags, and the tool reference. Then run stories 1–11 from Claude Code against the installed release binary.

**Acceptance criteria:**
- [ ] Following the README from scratch produces a working registered server.
- [ ] Stories 1–11 pass manually, and every SPEC Success Criteria item is checked.
- [ ] `swift format lint --recursive --strict Sources Tests` is clean.

**Verification:**
- [ ] Manual walkthrough, and `swift build -c release` with zero warnings

**Dependencies:** 12
**Files:** `README.md`, `SPEC.md`
**Scope:** S

## Checkpoint: Complete
- [ ] All SPEC Success Criteria are met.
- [ ] Ready for final review.
