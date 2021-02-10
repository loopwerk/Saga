import XCTest

import SagaTests

var tests = [XCTestCaseEntry]()
tests += SagaTests.allTests()
XCTMain(tests)
