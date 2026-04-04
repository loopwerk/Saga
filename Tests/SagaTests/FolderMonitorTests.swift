import Foundation
@testable import Saga
import SagaPathKit
import XCTest

class FolderMonitorTests: XCTestCase {
  func testMatchesGlobPattern() {
    // Exact filename match
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("output.css", patterns: ["output.css"]))
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("static/output.css", patterns: ["output.css"]))
    XCTAssertFalse(FolderMonitor.matchesGlobPattern("output.css", patterns: ["input.css"]))

    // Wildcard matches filename in root
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("style.css", patterns: ["*.css"]))

    // Wildcard matches filename in subdirectory
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("static/style.css", patterns: ["*.css"]))

    // FNM_PATHNAME: * doesn't cross / in full path match
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("static/style.css", patterns: ["static/*.css"]))
    XCTAssertFalse(FolderMonitor.matchesGlobPattern("static/sub/style.css", patterns: ["static/*.css"]))
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("static/sub/style.css", patterns: ["static/**/*.css"]))
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("static/sub/style.css", patterns: ["*.css"]))

    // No match
    XCTAssertFalse(FolderMonitor.matchesGlobPattern("style.css", patterns: ["*.js"]))

    // Multiple patterns, one matches
    XCTAssertTrue(FolderMonitor.matchesGlobPattern("style.css", patterns: ["*.js", "*.css"]))

    // Empty patterns
    XCTAssertFalse(FolderMonitor.matchesGlobPattern("style.css", patterns: []))
  }
}
