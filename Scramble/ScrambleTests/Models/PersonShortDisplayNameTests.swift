import Foundation
import Testing

@testable import Scramble

@Suite("Person.shortDisplayName")
@MainActor
struct PersonShortDisplayNameTests {

  private static func person(_ name: String) -> Person {
    Person(name: name, colorKey: "blue")
  }

  @Test("Single-word name returns the full name")
  func singleWord() {
    #expect(Self.person("Arjen").shortDisplayName == "Arjen")
  }

  @Test("Multi-word name returns the first space-separated token")
  func multiWord() {
    #expect(Self.person("Mary Jane Watson").shortDisplayName == "Mary")
  }

  @Test("Two-word name returns the first token")
  func twoWord() {
    #expect(Self.person("Peter Parker").shortDisplayName == "Peter")
  }

  @Test("Empty name returns '?'")
  func empty() {
    #expect(Self.person("").shortDisplayName == "?")
  }

  @Test("Whitespace-only name returns '?'")
  func whitespaceOnly() {
    #expect(Self.person("   ").shortDisplayName == "?")
  }

  @Test("Leading whitespace is trimmed before splitting")
  func leadingWhitespace() {
    #expect(Self.person("  Mary Jane").shortDisplayName == "Mary")
  }

  @Test("Trailing whitespace is trimmed before splitting")
  func trailingWhitespace() {
    #expect(Self.person("Arjen   ").shortDisplayName == "Arjen")
  }

  @Test("Single CJK character (no space) returns the full name")
  func singleCJK() {
    #expect(Self.person("林").shortDisplayName == "林")
  }

  @Test("Multi-character CJK with no spaces returns the full name (v1 space-split fallback)")
  func multiCJK() {
    #expect(Self.person("林志玲").shortDisplayName == "林志玲")
  }

  @Test("CJK with space-separated tokens returns the first token")
  func multiCJKWithSpace() {
    #expect(Self.person("林 志玲").shortDisplayName == "林")
  }
}
