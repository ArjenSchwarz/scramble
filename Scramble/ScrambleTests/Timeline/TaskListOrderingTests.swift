import Foundation
import Testing

@testable import Scramble

@Suite("TaskListHelpers.sorted")
@MainActor
struct TaskListOrderingTests {

  // MARK: - Fixture builder

  private static func task(
    name: String,
    completed: Bool = false,
    matches: Bool = true,
    pinned: Bool = false
  ) -> TripTask {
    TripTask(
      name: name,
      isCompleted: completed,
      source: .rule,
      currentlyMatchesRules: matches,
      pinnedByUser: pinned
    )
  }

  // MARK: - Req 5.1: four-group order

  @Test(
    "Req 5.1: incomplete-matching first, then completed-matching, then incomplete-unmatching, then completed-unmatching"
  )
  func fourGroupOrder() {
    // Build one task per bucket. Names are all unique so there's no within-bucket tiebreaking ambiguity.
    let incompleteMatching = Self.task(name: "alpha", completed: false, matches: true)
    let completedMatching = Self.task(name: "beta", completed: true, matches: true)
    let incompleteUnmatching = Self.task(name: "gamma", completed: false, matches: false)
    let completedUnmatching = Self.task(name: "delta", completed: true, matches: false)

    let input = [completedUnmatching, incompleteUnmatching, completedMatching, incompleteMatching]
    let result = TaskListHelpers.sorted(input)

    #expect(result.map(\.name) == ["alpha", "beta", "gamma", "delta"])
  }

  @Test("Pinned-but-unmatched tasks sit in the matching bucket (matching = matches || pinned)")
  func pinnedUnmatchedInMatchingBucket() {
    let pinnedUnmatched = Self.task(
      name: "alpha-pinned", completed: false, matches: false, pinned: true)
    let plainMatching = Self.task(
      name: "beta-matching", completed: false, matches: true, pinned: false)
    let plainUnmatched = Self.task(
      name: "gamma-plain-unmatched", completed: false, matches: false, pinned: false)

    let input = [plainUnmatched, pinnedUnmatched, plainMatching]
    let result = TaskListHelpers.sorted(input)

    // Both the pinned-unmatched and the plain-matching are in bucket 1; ordering within
    // the matching-or-pinned + incomplete bucket is by name ascending.
    #expect(result.map(\.name) == ["alpha-pinned", "beta-matching", "gamma-plain-unmatched"])
  }

  @Test("Pinned-and-completed unmatched sits in completed-matching bucket")
  func pinnedCompletedUnmatched() {
    let pinnedCompletedUnmatched = Self.task(
      name: "pinned-done", completed: true, matches: false, pinned: true)
    let plainMatching = Self.task(name: "plain-matching", completed: false, matches: true)
    let plainUnmatched = Self.task(name: "plain-unmatched", completed: false, matches: false)
    let input = [plainUnmatched, pinnedCompletedUnmatched, plainMatching]
    let result = TaskListHelpers.sorted(input)

    // plain-matching (incomplete-matching) → pinned-done (completed-matching) → plain-unmatched (incomplete-unmatching)
    #expect(result.map(\.name) == ["plain-matching", "pinned-done", "plain-unmatched"])
  }

  // MARK: - Req 5.2: case-insensitive name sort within bucket (incl. non-ASCII)

  @Test("Req 5.2: case-insensitive ascending name sort within a bucket")
  func caseInsensitiveSort() {
    let inputs = [
      Self.task(name: "beta"),
      Self.task(name: "Alpha"),
      Self.task(name: "alpha"),
    ]
    let result = TaskListHelpers.sorted(inputs)
    // All three are in the incomplete-matching bucket. Within-bucket sort is
    // case-insensitive; "Alpha" and "alpha" compare equal — relative order
    // is allowed to be either, so we just assert "beta" comes last.
    #expect(result.last?.name == "beta")
    let lowerNames = result.map { $0.name.lowercased() }
    #expect(lowerNames == ["alpha", "alpha", "beta"])
  }

  @Test("Req 5.2: non-ASCII names sort by locale-aware case-insensitive compare")
  func nonASCIISort() {
    let inputs = [
      Self.task(name: "Beta"),
      Self.task(name: "Étretat"),
      Self.task(name: "alpha"),
    ]
    let result = TaskListHelpers.sorted(inputs)
    // localizedCaseInsensitiveCompare places "alpha", "Beta", "Étretat" in that order in en/en-US.
    #expect(result.map(\.name) == ["alpha", "Beta", "Étretat"])
  }

  @Test("Mixed case + non-ASCII across all four buckets keeps each bucket internally sorted")
  func mixedAcrossBuckets() {
    let inputs = [
      Self.task(name: "zebra", completed: true, matches: false),  // bucket 4 (completed-unmatching)
      Self.task(name: "Étretat", completed: false, matches: false),  // bucket 3 (incomplete-unmatching)
      Self.task(name: "Charlie", completed: true, matches: true),  // bucket 2 (completed-matching)
      Self.task(name: "beta", completed: false, matches: true),  // bucket 1 (incomplete-matching)
      Self.task(name: "Alpha", completed: false, matches: true),  // bucket 1 (incomplete-matching)
    ]
    let result = TaskListHelpers.sorted(inputs)
    #expect(result.map(\.name) == ["Alpha", "beta", "Charlie", "Étretat", "zebra"])
  }
}
