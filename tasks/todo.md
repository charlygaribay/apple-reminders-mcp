# Tasks: Apple Reminders MCP Server

> Plan: [plan.md](plan.md) · Spec: [SPEC.md](../SPEC.md)
> Standing verification for every task: `scripts/build.sh` (zero warnings) and `scripts/test.sh` pass.

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

### Task 3: `EventKitStore`, permission handling, the launcher, and a real `list_lists`

**Description:** Implement the `EventKitStore` actor (`ensureAccess()` and `listLists()`), embed `Info.plist`, and wire the real store into the entry point. Add the `apple-reminders-mcp-launch` launcher, which makes the server its own TCC-responsible process, and `scripts/build.sh`, which signs both binaries with a stable identity. Add an end-to-end integration test that drives the built launcher over stdio.

*Revised during the task. MCP clients have no Reminders usage description, so macOS refused access silently, and ad-hoc signatures lost the grant on every rebuild. See SPEC Resolved Decisions 4–6.*

**Acceptance criteria:**
- [x] Launched through the launcher, macOS prompts for **apple-reminders-mcp**, and `list_lists` returns the real lists. Launched directly by Claude Code, the server returns the access-denied guidance instead of crashing.
- [x] `otool -s __TEXT __info_plist` on the server binary shows the embedded usage description.
- [x] The end-to-end `list_lists` test passes against real Reminders. It's read-only, so it creates nothing.
- [x] With the `apple-reminders-mcp dev` certificate in place, rebuilding twice with `scripts/build.sh` doesn't re-prompt. *(Two content-changing rebuilds, each end-to-end run < 1 s, no prompt.)*

**Verification:**
- [x] `scripts/test.sh` (unit + launcher tests)
- [x] `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests`
- [x] `codesign -dvv .build/debug/apple-reminders-mcp` shows `Authority=apple-reminders-mcp dev`, not `adhoc`

**Dependencies:** 2
**Files:** `Sources/RemindersEventKit/*`, `Sources/apple-reminders-mcp/{AppleRemindersMCP.swift,Info.plist}`, `Sources/apple-reminders-mcp-launch/Launcher.swift`, `Package.swift`, `scripts/{build,sign,test}.sh`, `Tests/IntegrationTests/*`, `Tests/LauncherTests/*`, `Tests/Support/ClientHelpers.swift`
**Scope:** L. It grew during de-risking.

## Checkpoint 1: Foundation
- [x] All tests pass and the build is clean.
- [ ] `list_lists` returns real data from Claude Code, registered through the launcher. *(Registering changes your Claude Code config, so it's left for you to run.)*
- [x] The grant survives a rebuild (signing).
- [ ] **Review with the human before proceeding.**

## Phase 2: List management & the end-to-end test harness

### Task 4: `create_list`, `delete_list`, and the `--allow-delete` gate (fake store)

**Description:** Add `createList(title:sourceTitle:)` and `deleteList(id:confirmTitle:)` to the protocol and fake. Add a minimal `ServerMode` with `.standard` and `.allowDelete` (from `--allow-delete` or `REMINDERS_MCP_ALLOW_DELETE=1`), and have `ToolRegistry` filter tools by mode, with a dispatcher guard. Implement the `create_list` and `delete_list` tools (`delete_list` carries `destructiveHint`).

**Acceptance criteria:**
- [ ] The default mode lists `list_lists` and `create_list`, but not `delete_list`. `--allow-delete` adds `delete_list`, and calling `delete_list` by name without the flag produces `isError`.
- [ ] `create_list` with an empty or whitespace title, or with an unknown `sourceTitle`, produces `isError`. The unknown-source error names the valid sources.
- [ ] `delete_list` with a mismatched `confirmTitle` produces `isError` and the list survives. A matching title removes it.

**Verification:**
- [ ] `scripts/test.sh --filter ServerTests`

**Dependencies:** 3
**Files:** `Sources/RemindersCore/RemindersStore.swift`, `Sources/apple-reminders-mcp/{ServerMode.swift,ToolRegistry.swift,AppleRemindersMCP.swift}`, `Sources/apple-reminders-mcp/Tools/{CreateList,DeleteList}.swift`, `Tests/Support/FakeRemindersStore.swift`, `Tests/ServerTests/ListManagementTests.swift`
**Scope:** M

### Task 5: EventKit `createList` / `deleteList` and the throwaway-list harness

**Description:** Implement both operations in `EventKitStore`. The default source comes from `defaultCalendarForNewReminders()`. Immutable lists throw `readOnlyList`. Add `withThrowawayList` to the integration tests: it starts the server with `--allow-delete`, creates `MCP Test <uuid>` through `create_list`, runs the test body, and always deletes the list through `delete_list`.

**Acceptance criteria:**
- [ ] An end-to-end test creates a throwaway list and sees it in `list_lists`, and after teardown it's gone.
- [ ] Teardown runs even when the test body throws (verified with a deliberately failing body).
- [ ] After the full integration run, no `MCP Test` lists remain.

**Verification:**
- [ ] `REMINDERS_MCP_INTEGRATION=1 scripts/test.sh --filter IntegrationTests`

**Dependencies:** 4
**Files:** `Sources/RemindersEventKit/EventKitStore.swift`, `Tests/IntegrationTests/{ThrowawayList.swift,ListManagementEndToEndTests.swift}`
**Scope:** S

### Task 6: `rename_list`

**Description:** Add `renameList(id:title:)` to the protocol, fake, and EventKit store, plus the tool.

**Acceptance criteria:**
- [ ] `rename_list` changes the title, and `list_lists` reflects it.
- [ ] An empty title, an unknown id, or an immutable list produces a specific `isError`.
- [ ] An end-to-end test renames a throwaway list.

**Verification:**
- [ ] `scripts/test.sh` and the integration tests

**Dependencies:** 5
**Files:** `Sources/RemindersCore/RemindersStore.swift`, `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/RenameList.swift`, `Tests/ServerTests/ListManagementTests.swift`, `Tests/IntegrationTests/ListManagementEndToEndTests.swift`
**Scope:** S

## Checkpoint 2: Lists
- [ ] Stories 1 and 7 work from Claude Code. The integration run leaves no `MCP Test` lists behind.

## Phase 3: Reminders, read and create

### Task 7: Due-date coding and priority mapping in Core

**Description:** Add the `DueDate` enum with ISO 8601 parsing and formatting (date-only `YYYY-MM-DD`, and date-time with an offset or `Z`), conversion to and from `DateComponents`, and the `Priority` enum with EventKit integer mapping (0/9/5/1, with 1–4 → high, 5 → medium, 6–9 → low on read).

**Acceptance criteria:**
- [ ] Round-trip tests pass for date-only, date-time with an offset, and UTC `Z`. Invalid strings throw `invalidArgument` with the bad value in the message.
- [ ] Date-only produces `DateComponents` with no hour or minute.
- [ ] Every EventKit priority value 0–9 maps to the right `Priority`, and back.

**Verification:**
- [ ] `scripts/test.sh --filter RemindersCoreTests`

**Dependencies:** 1 (can run in parallel with tasks 4–6)
**Files:** `Sources/RemindersCore/DueDateCoding.swift`, `Sources/RemindersCore/Models.swift`, `Tests/RemindersCoreTests/{DueDateCodingTests,PriorityTests}.swift`
**Scope:** S

### Task 8: `create_reminder` and `get_reminder`

**Description:** Add `ReminderDTO` with all v1 fields, a validated `NewReminder` (non-empty title, valid URL), and the EKReminder → DTO mapping. Add `createReminder` and `getReminder` to the protocol, fake, and EventKit store, plus both tools. These are one slice because end-to-end, a reminder has to be created before it can be read back.

**Acceptance criteria:**
- [ ] Creating with only a title lands in the default list (unit test, using the fake). Creating with every field in the throwaway list round-trips through `get_reminder` end to end.
- [ ] An empty title, an invalid date or URL, an unknown `listId`, or a read-only list each produce a specific `isError`.
- [ ] `get_reminder` with an unknown id produces "reminder not found: <id>".

**Verification:**
- [ ] `scripts/test.sh` and the integration tests

**Dependencies:** 5, 7
**Files:** `Sources/RemindersCore/Models.swift`, `Sources/RemindersEventKit/{EventKitStore,EventKitMapping}.swift`, `Sources/apple-reminders-mcp/Tools/{CreateReminder,GetReminder}.swift`, `Tests/ServerTests/RemindersTests.swift`, `Tests/IntegrationTests/RemindersEndToEndTests.swift`
**Scope:** M

### Task 9: `list_reminders` with filters, the 30-day completed default, and truncation

**Description:** Add a `ReminderQuery` in Core with validation: limit 1–500 (default 50), range order, and status. Add a shared in-memory filter covering text, overdue, and limit/truncation. On the EventKit side, use predicates scoped to the requested lists (incomplete by due range, completed by completion range, defaulting to the last 30 days). The tool returns `{ reminders, truncated, totalMatched }`.

**Acceptance criteria:**
- [ ] Each filter (lists, status, due range, overdue, completion range, text) has a passing test against the fake, both alone and in combination.
- [ ] `status: completed` with no completion range excludes a reminder completed 31 days ago and includes one completed 29 days ago.
- [ ] `limit` 0 or 501 produces `isError`. More matches than `limit` sets `truncated: true` with the correct `totalMatched`. An end-to-end query scoped to the throwaway list returns only its reminders.

**Verification:**
- [ ] `scripts/test.sh` and the integration tests
- [ ] Manual: ask Claude "what's due this week?"

**Dependencies:** 8
**Files:** `Sources/RemindersCore/ReminderQuery.swift`, `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/ListReminders.swift`, `Tests/RemindersCoreTests/ReminderQueryTests.swift`, `Tests/ServerTests/ListRemindersTests.swift`
**Scope:** M

## Checkpoint 3: Read & create
- [ ] Stories 1–4 work from Claude Code.
- [ ] **Review with the human before proceeding.**

## Phase 4: Updating reminders

### Task 10: `update_reminder` (partial patch and move) and `set_reminder_completed`

**Description:** Add `FieldPatch<T>` tri-state decoding and a `ReminderPatch`. Implement `updateReminder` (including a `listId` move) and `setCompleted` in the protocol, fake, and EventKit store, plus both tools.

**Acceptance criteria:**
- [ ] An absent field stays unchanged, `null` clears it (notes, dueDate, url, priority → none), and a value sets it. `title: null` produces `isError`.
- [ ] Moving to another list via `listId` works (end to end, between two throwaway lists). Moving to a read-only or unknown list produces `isError`.
- [ ] `set_reminder_completed` toggles both ways and sets or clears `completedAt`.

**Verification:**
- [ ] `scripts/test.sh` and the integration tests

**Dependencies:** 9
**Files:** `Sources/RemindersCore/FieldPatch.swift`, `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/{UpdateReminder,SetReminderCompleted}.swift`, `Tests/ServerTests/UpdateReminderTests.swift`
**Scope:** M

## Phase 5: Remaining modes & deletes

### Task 11: `--read-only` mode, the env vars, and the conflict check

**Description:** Extend `ServerMode` with `.readOnly` (from `--read-only` or `REMINDERS_MCP_READ_ONLY=1`). Combining it with allow-delete, by flag or env var, exits non-zero with a message on stderr before serving.

**Acceptance criteria:**
- [ ] Read-only mode lists exactly `list_lists`, `list_reminders`, and `get_reminder`. Calling `create_reminder` by name produces `isError` "not available in read-only mode".
- [ ] `--read-only --allow-delete`, or the env-var equivalent, exits non-zero.
- [ ] The default mode lists 8 tools (once task 12 lands, allow-delete lists 10).

**Verification:**
- [ ] `scripts/test.sh --filter ServerModeTests`
- [ ] `.build/debug/apple-reminders-mcp-launch --read-only --allow-delete; echo $?` prints non-zero

**Dependencies:** 10
**Files:** `Sources/apple-reminders-mcp/{ServerMode,ToolRegistry,AppleRemindersMCP}.swift`, `Tests/ServerTests/ServerModeTests.swift`
**Scope:** S

### Task 12: `delete_reminder`

**Description:** Add `deleteReminder(id:)` to the protocol, fake, and EventKit store, plus the tool. It's registered only under allow-delete, with `destructiveHint`.

**Acceptance criteria:**
- [ ] With `--allow-delete`, 10 tools are listed. Without it, `delete_reminder` is absent and calling it produces `isError`.
- [ ] An unknown id produces `isError`. An end-to-end test deletes a reminder from the throwaway list, and `get_reminder` then reports it as not found.

**Verification:**
- [ ] `scripts/test.sh` and the integration tests

**Dependencies:** 11
**Files:** `Sources/RemindersEventKit/EventKitStore.swift`, `Sources/apple-reminders-mcp/Tools/DeleteReminder.swift`, `Tests/ServerTests/DeleteTests.swift`, `Tests/IntegrationTests/RemindersEndToEndTests.swift`
**Scope:** S

## Checkpoint 4: All tools
- [ ] Through the launcher, Inspector shows 8 / 10 / 3 tools by mode, and passing both flags exits non-zero.

## Phase 6: Hardening & docs

### Task 13: Access-denied UX check and performance check

**Description:** You revoke Reminders access for apple-reminders-mcp in System Settings (I don't touch privacy settings). Confirm every tool returns the guidance error with the process still alive, then you restore access. Add a read-only timing test that runs `list_reminders` with `status: all` across the real store.

**Acceptance criteria:**
- [ ] With access revoked, all 10 tools return `isError` with the guidance, and the server keeps responding.
- [ ] `list_reminders` across ~1,000 reminders finishes in < 2 s. Record the measured time in SPEC.md.

**Verification:**
- [ ] Manual, through Inspector. The timing is printed by an integration test that only reads.

**Dependencies:** 12
**Files:** `Tests/IntegrationTests/PerformanceTests.swift`, `SPEC.md`
**Scope:** S

### Task 14: README, install, and the final manual smoke test

**Description:** Write a README covering prerequisites, creating the signing certificate, build, installing both binaries to `~/.local/bin`, the one-time permission prompt, Claude Code and Claude Desktop registration (via the launcher), the mode flags, and the tool reference. Then run stories 1–11 from Claude Code against the installed release binaries.

**Acceptance criteria:**
- [ ] Following the README from scratch produces a working registered server.
- [ ] Stories 1–11 pass manually, and every SPEC Success Criteria item is checked.
- [ ] `swift format lint --recursive --strict Sources Tests` is clean.

**Verification:**
- [ ] Manual walkthrough, and `scripts/build.sh -c release` with zero warnings

**Dependencies:** 13
**Files:** `README.md`, `SPEC.md`
**Scope:** S

## Checkpoint: Complete
- [ ] All SPEC Success Criteria are met.
- [ ] Ready for final review.
