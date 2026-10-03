/// What a tool does to Reminders data. Decides both its MCP annotations and whether a
/// server mode exposes it.
enum ToolAccess: Sendable {
  case read
  case write
  /// Irreversible removal; only exposed when deletes are explicitly allowed.
  case delete
}

/// Which tools the server exposes, fixed at startup.
enum ServerMode: Equatable, Sendable {
  case standard
  case allowDelete

  static let allowDeleteVariable = "REMINDERS_MCP_ALLOW_DELETE"

  static func resolve(allowDeleteFlag: Bool, environment: [String: String]) -> ServerMode {
    allowDeleteFlag || environment[allowDeleteVariable] == "1" ? .allowDelete : .standard
  }

  func allows(_ access: ToolAccess) -> Bool {
    switch access {
    case .read, .write: true
    case .delete: self == .allowDelete
    }
  }

  /// Why a tool with `access` is hidden in this mode, for callers that use it by name anyway.
  func unavailableReason(for access: ToolAccess) -> String {
    switch access {
    case .delete:
      "it deletes data; start the server with --allow-delete (or \(Self.allowDeleteVariable)=1)"
    case .read, .write:
      "it isn't enabled in this server mode"
    }
  }
}
