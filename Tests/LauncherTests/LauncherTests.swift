import Foundation
import Testing

@testable import apple_reminders_mcp_launch

@Suite struct LauncherTests {
  @Test func serverIsResolvedNextToLauncher() {
    #expect(
      Launcher.serverPath(forLauncherAt: "/opt/bin/apple-reminders-mcp-launch")
        == "/opt/bin/apple-reminders-mcp")
  }

  @Test func symlinkedLauncherResolvesToRealDirectory() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("launcher-test-\(UUID().uuidString)")
    let real = base.appendingPathComponent("real")
    let linkDir = base.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let launcher = real.appendingPathComponent("apple-reminders-mcp-launch")
    FileManager.default.createFile(atPath: launcher.path, contents: Data())
    let link = linkDir.appendingPathComponent("apple-reminders-mcp-launch")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: launcher)

    #expect(
      Launcher.serverPath(forLauncherAt: link.path)
        == real.resolvingSymlinksInPath().appendingPathComponent("apple-reminders-mcp").path)
  }
}
