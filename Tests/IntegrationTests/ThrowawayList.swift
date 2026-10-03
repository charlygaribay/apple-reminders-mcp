import Foundation
import MCP
import RemindersCore
import TestSupport

enum HarnessError: Error, CustomStringConvertible {
  case cleanupFailed(listTitle: String, underlying: any Error)
  case refusedToDelete(listTitle: String)

  var description: String {
    switch self {
    case .cleanupFailed(let title, let underlying):
      "couldn't delete throwaway list '\(title)'; remove it by hand. Cause: \(underlying)"
    case .refusedToDelete(let title):
      "refusing to delete '\(title)': not a throwaway list"
    }
  }
}

extension ServerProcess {
  static let throwawayPrefix = "MCP Test "

  /// Runs `body` against a fresh server and always stops it afterwards.
  /// Deletes are allowed by default because the throwaway-list teardown needs `delete_list`.
  static func with<T>(
    arguments: [String] = ["--allow-delete"],
    _ body: (ServerProcess) async throws -> T
  ) async throws -> T {
    let server = try await start(arguments: arguments)
    do {
      let result = try await body(server)
      await server.stop()
      return result
    } catch {
      await server.stop()
      throw error
    }
  }

  /// Creates a uniquely named list, runs `body`, and always deletes the list afterwards.
  /// Tests must only create or modify reminders inside this list.
  func withThrowawayList<T>(
    sourceTitle: String? = nil,
    _ body: (ReminderListDTO) async throws -> T
  ) async throws -> T {
    var arguments: [String: Value] = ["title": .string(Self.throwawayPrefix + UUID().uuidString)]
    if let sourceTitle { arguments["sourceTitle"] = .string(sourceTitle) }
    let list = try await client.callDecoding(ListPayload.self, "create_list", arguments).list

    let outcome: Result<T, any Error>
    do {
      outcome = .success(try await body(list))
    } catch {
      outcome = .failure(error)
    }
    try await deleteThrowawayList(id: list.id, originalTitle: list.title)
    return try outcome.get()
  }

  /// Deletes by id using the list's *current* title, since a test may have renamed it.
  private func deleteThrowawayList(id: String, originalTitle: String) async throws {
    do {
      let lists = try await client.callDecoding(ListsPayload.self, "list_lists").lists
      guard let current = lists.first(where: { $0.id == id }) else { return }  // Already gone.
      // Never delete anything that doesn't look like ours, whatever the id says.
      guard current.title.hasPrefix(Self.throwawayPrefix) else {
        throw HarnessError.refusedToDelete(listTitle: current.title)
      }
      _ = try await client.callDecoding(
        DeletedListPayload.self, "delete_list",
        ["id": .string(id), "confirmTitle": .string(current.title)])
    } catch let error as HarnessError {
      throw error
    } catch {
      throw HarnessError.cleanupFailed(listTitle: originalTitle, underlying: error)
    }
  }

  func listIDs() async throws -> Set<String> {
    Set(try await client.callDecoding(ListsPayload.self, "list_lists").lists.map(\.id))
  }
}
