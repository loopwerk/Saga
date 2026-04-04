import SagaPathKit

/// Describes why the current build was triggered.
public enum BuildReason: Sendable {
  /// First build when the process starts (cold start).
  case initial

  /// A non-Swift content/asset file changed during dev mode.
  case fileChange(Path)

  /// A Swift source file changed, triggering recompilation and relaunch.
  case recompile(Path)

  /// Returns the path of the file that triggered this build, if any.
  public func changedFile() -> Path? {
    switch self {
      case .initial:
        return nil
      case .fileChange(let path), .recompile(let path):
        return path
    }
  }
}
