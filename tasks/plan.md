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
- **Launcher:** `apple-reminders-mcp-launch` re-execs the sibling server in place, disclaiming TCC responsibility, so macOS attributes the request to the server and not to the MCP client. It's the only code that uses private API.
- **Stable signing:** `scripts/build.sh` signs both binaries with the `apple-reminders-mcp dev` identity, so the grant (which macOS ties to the signature) survives rebuilds.
- **End-to-end integration tests:** these drive the built launcher over stdio with the SDK client. The test runner itself can't get Reminders access.

## Task List

*Reordered after task 3 (2026-10-03). Integration tests now run end to end through the launcher, and their throwaway-list harness needs `create_list` and `delete_list`, so list management moves up. Details are in [todo.md](todo.md).*

### Phase 1: Foundation & de-risking
- [x] Task 1: Package skeleton, test harness, and a server that boots over stdio
- [x] Task 2: Core store protocol, tool registry, and `list_lists` against the fake store
- [x] Task 3: `EventKitStore`, permission handling, the launcher, and a real `list_lists`

### Checkpoint 1: Foundation
- [ ] `list_lists` works from Claude Code via the launcher, and the grant survives a rebuild. Review with the human.

### Phase 2: List management & the end-to-end test harness
- [x] Task 4: `create_list`, `delete_list`, and the `--allow-delete` gate (fake store)
- [x] Task 5: EventKit `createList` / `deleteList` and the throwaway-list harness
- [x] Task 6: `rename_list`

### Checkpoint 2: Lists
- [ ] Stories 1 and 7 work. The integration run leaves no `MCP Test` lists behind.

### Phase 3: Reminders, read and create
- [x] Task 7: Due-date coding and priority mapping in Core
- [ ] Task 8: `create_reminder` and `get_reminder`
- [ ] Task 9: `list_reminders` with filters, the 30-day completed default, and truncation

### Checkpoint 3: Read & create
- [ ] Stories 1–4 work from Claude Code. Review with the human.

### Phase 4: Updating reminders
- [ ] Task 10: `update_reminder` (partial patch and move) and `set_reminder_completed`

### Phase 5: Remaining modes & deletes
- [ ] Task 11: `--read-only` mode, the env vars, and the conflict check
- [ ] Task 12: `delete_reminder`

### Checkpoint 4: All tools
- [ ] Tool counts are 8 / 10 / 3 by mode. Passing both flags exits non-zero.

### Phase 6: Hardening & docs
- [ ] Task 13: Access-denied UX check and performance check
- [ ] Task 14: README, install, and the final manual smoke test

### Checkpoint: Complete
- [ ] Every Success Criteria item in SPEC.md is checked.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| ~~Swift Testing doesn't run under Command Line Tools alone~~ | — | Resolved in task 1 by `scripts/test.sh`. |
| ~~The Reminders prompt never appears for a stdio child process~~ | — | Confirmed in task 3 (refused silently, attributed to Claude Code). Resolved by the launcher. |
| The private disclaim API changes in a future macOS | Med | The lookup is at runtime. On failure the launcher warns and execs normally, and the server returns its access-denied guidance. |
| The grant is lost on rebuild or upgrade (ad-hoc signature) | Med | Stable self-signed identity via `scripts/build.sh`. |
| `swift-sdk` 0.12.x API differs from what's expected | Med | Pin `.upToNextMinor(from: "0.12.1")`. Task 1 confirms the server/transport API before anything else gets built on it. |
| Integration tests touch real data | High | Each test only writes inside a UUID-named list it created via `create_list`. Teardown always deletes it via `delete_list`. Assertions are scoped to that list's id. |
| EventKit fetches are slow on big stores | Low | Calendar-scoped predicates plus the 30-day completed default. Measured in task 12. |
| Shared / read-only lists | Low | Check `allowsContentModifications` and throw `readOnlyList`. Covered in tasks 7–9. |

## Parallelization

The work is mostly sequential, because the registry and store protocol in task 2 are shared contracts. After Checkpoint 1, task 4 (pure Core) can run alongside task 3's follow-ups, and task 13's README draft can start any time after Checkpoint 3.

## Open Questions

None. All spec questions were resolved on 2026-10-02.
