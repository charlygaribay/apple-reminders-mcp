import Darwin
import Foundation

/// Execs `apple-reminders-mcp` (installed next to this binary) as its own TCC-responsible
/// process, forwarding all arguments and the environment.
///
/// macOS attributes privacy prompts to the process that launched a command-line tool. MCP
/// clients such as Claude Code have no Reminders usage description, so TCC refuses access
/// without prompting. Disclaiming responsibility makes macOS prompt for the server itself,
/// using the Info.plist embedded in its binary. This private API is confined to this launcher.
@main
enum Launcher {
  static let serverName = "apple-reminders-mcp"

  static func main() {
    guard let launcherPath = Bundle.main.executablePath else {
      fail("can't determine the launcher's own path")
    }
    let server = serverPath(forLauncherAt: launcherPath)
    guard FileManager.default.isExecutableFile(atPath: server) else {
      fail("server binary not found at \(server); install it next to the launcher")
    }
    let arguments = [server] + CommandLine.arguments.dropFirst()
    let errorCode = execDisclaimingResponsibility(path: server, arguments: arguments)
    fail("failed to exec \(server): \(String(cString: strerror(errorCode)))")
  }

  /// The server lives in the same directory as the (symlink-resolved) launcher.
  static func serverPath(forLauncherAt launcherPath: String) -> String {
    URL(fileURLWithPath: launcherPath)
      .resolvingSymlinksInPath()
      .deletingLastPathComponent()
      .appendingPathComponent(serverName)
      .path
  }

  /// Replaces this process with `path`. Only returns (with an errno) on failure.
  private static func execDisclaimingResponsibility(path: String, arguments: [String]) -> Int32 {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETEXEC))

    if let setDisclaim = lookUpSetDisclaim() {
      _ = setDisclaim(&attributes, 1)
    } else {
      warn("responsibility_spawnattrs_setdisclaim unavailable; Reminders access may be refused")
    }

    let argv = arguments.map { strdup($0) } + [nil]
    defer { for arg in argv { free(arg) } }
    var pid: pid_t = 0
    return posix_spawn(&pid, path, nil, &attributes, argv, environ)
  }

  private typealias SetDisclaim =
    @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

  private static func lookUpSetDisclaim() -> SetDisclaim? {
    guard
      let symbol = dlsym(
        UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
    else { return nil }
    return unsafeBitCast(symbol, to: SetDisclaim.self)
  }

  private static func warn(_ message: String) {
    FileHandle.standardError.write(Data("[\(serverName)-launch] \(message)\n".utf8))
  }

  private static func fail(_ message: String) -> Never {
    warn(message)
    exit(1)
  }
}
