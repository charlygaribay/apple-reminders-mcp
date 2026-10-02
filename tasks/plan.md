# Implementation Plan: Apple Reminders MCP Server

> Source of truth: [SPEC.md](../SPEC.md) (approved 2026-10-02). Tasks live in [todo.md](todo.md).

## Overview

A Swift 6 SwiftPM package that produces one stdio MCP binary, `apple-reminders-mcp`. The work proceeds in vertical slices: each task wires a single tool through every layer (Core types → fake store → EventKit store → tool handler → tests). That way the server stays runnable after every task. The two biggest unknowns, Swift Testing without Xcode and the Reminders permission grant for a CLI binary, are tackled in tasks 1 and 3 so they fail fast.

## Architecture Decisions

- **Three targets, one direction:** `apple-reminders-mcp` → `RemindersEventKit` → `RemindersCore`. Core imports only Foundation, so ~90% of the logic is unit-testable with no Reminders access.
- **`RemindersStore` protocol is the seam.** `EventKitStore` (an actor) is used in production. `FakeRemindersStore` (an in-memory actor in test support) is used for unit tests. The tool handlers only see the protocol.
- **Single error-mapping point.** Store methods throw `RemindersError`. `ToolRegistry`'s dispatcher is the only place that turns errors into `isError: true` tool results. Anything else that's unexpected becomes a generic `isError` result with the error description, never a crash.
- **Mode is computed once at startup.** A `ServerMode` (`.standard`, `.allowDelete`, `.readOnly`) is resolved from flags and env vars, and an invalid combination exits non-zero before the server starts. `ToolRegistry.tools(for:)` filters the tool list. The dispatcher re-checks the mode too, so a hidden tool that gets called by name is rejected.
- **Patch semantics:** `update_reminder` decodes each optional field as a tri-state `FieldPatch<T>` (`.unchanged` / `.clear` / `.set(T)`). This keeps "absent" distinct from `null`.
- **Due dates:** Core's `DueDate` enum has two cases, `.date(y,m,d)` and `.dateTime(Date)`. It maps to `DateComponents` (date-only means no hour/minute) so Reminders.app shows "all-day" vs timed correctly.
- **Query execution:** EventKit predicates handle the coarse filtering (incomplete with a due range, completed with a completion range defaulting to the last 30 days, scoped to calendars). Text match, overdue, and limit/truncation are applied in memory in Core. That way the same filtering code is tested against the fake store.
- **Permission:** the `Info.plist` with `NSRemindersFullAccessUsageDescription` is embedded through linker `-sectcreate` flags in `Package.swift`. `ensureAccess()` caches the granted state per process.

## Task List

### Phase 1: Foundation & de-risking
- [ ] Task 1: Package skeleton, test harness, and a server that boots over stdio
- [ ] Task 2: Core store protocol, tool registry, and `list_lists` against the fake store
- [ ] Task 3: `EventKitStore` with permission handling and a real `list_lists`

### Checkpoint 1: Foundation
- [ ] `swift build` and `scripts/test.sh` are clean. Swift Testing confirmed working with Command Line Tools.
- [ ] Claude Code (or Inspector) calls `list_lists` and sees real lists. The permission prompt works.
- [ ] Review with the human before continuing.

### Phase 2: Read path
- [ ] Task 4: Due-date coding and priority mapping in Core
- [ ] Task 5: `get_reminder` end to end
- [ ] Task 6: `list_reminders` with filters, the 30-day completed default, and truncation

### Checkpoint 2: Read path
- [ ] All 3 read tools work from Claude Code against real data.

### Phase 3: Write path
- [ ] Task 7: `create_reminder` end to end
- [ ] Task 8: `update_reminder` (partial patch and move) and `set_reminder_completed`
- [ ] Task 9: `create_list` and `rename_list`

### Checkpoint 3: Write path
- [ ] Stories 1–7 work from Claude Code. The integration suite passes and leaves no test list behind.

### Phase 4: Modes & destructive tools
- [ ] Task 10: Server modes (`--read-only`, `--allow-delete`, env vars, conflict check)
- [ ] Task 11: `delete_reminder` and `delete_list` (gated, with `confirmTitle`)

### Checkpoint 4: Modes
- [ ] Tool counts are 8 / 10 / 3 by mode. Passing both flags exits non-zero.

### Phase 5: Hardening & docs
- [ ] Task 12: Access-denied UX check and performance check
- [ ] Task 13: README, install, and the final manual smoke test of all stories

### Checkpoint: Complete
- [ ] Every Success Criteria item in SPEC.md is checked.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Swift Testing doesn't run under Command Line Tools alone | High | Task 1 proves it first. Fallback: install Xcode (ask the human). |
| The Reminders permission prompt never appears for a stdio child process, or it's attributed to the wrong app | High | Task 3: embed `Info.plist`, then test from both Terminal and Claude Code. Document which app needs the grant in System Settings. |
| `swift-sdk` 0.12.x API differs from what's expected | Med | Pin `.upToNextMinor(from: "0.12.1")`. Task 1 confirms the server/transport API before anything else gets built on it. |
| Integration tests touch real data | High | Each test only operates on a list it created (a UUID-named list). Teardown deletes that list. Integration tests never query outside that list's id. |
| EventKit fetches are slow on big stores | Low | Calendar-scoped predicates plus the 30-day completed default. Measured in task 12. |
| Shared / read-only lists | Low | Check `allowsContentModifications` and throw `readOnlyList`. Covered in tasks 7–9. |

## Parallelization

The work is mostly sequential, because the registry and store protocol in task 2 are shared contracts. After Checkpoint 1, task 4 (pure Core) can run alongside task 3's follow-ups, and task 13's README draft can start any time after Checkpoint 3.

## Open Questions

None. All spec questions were resolved on 2026-10-02.
