import Foundation
import Testing

@testable import Scramble

@Suite("PhaseCounts and subline")
@MainActor
struct PhaseCountsTests {

  // MARK: - Fixture builder

  private static func task(
    name: String = "t",
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

  // MARK: - counts()

  @Test("total = matching-or-pinned count; completed = subset that is also isCompleted")
  func basicCounts() {
    let tasks = [
      Self.task(name: "a", completed: false, matches: true),
      Self.task(name: "b", completed: true, matches: true),
      Self.task(name: "c", completed: false, matches: false, pinned: true),
      Self.task(name: "d", completed: false, matches: false),
      Self.task(name: "e", completed: true, matches: false)
    ]
    let counts = TaskListHelpers.counts(tasks)
    // matching-or-pinned: a (matches), b (matches+completed), c (pinned) → total 3, completed 1 (b)
    // unmatched-non-pinned: d, e → inactive 2
    #expect(counts.total == 3)
    #expect(counts.completed == 1)
    #expect(counts.inactive == 2)
  }

  @Test("Zero matching, zero inactive (empty list)")
  func zeroEmpty() {
    let counts = TaskListHelpers.counts([])
    #expect(counts.total == 0)
    #expect(counts.completed == 0)
    #expect(counts.inactive == 0)
  }

  @Test("Zero inactive when every task is matching-or-pinned")
  func zeroInactive() {
    let tasks = [
      Self.task(name: "a", matches: true),
      Self.task(name: "b", matches: false, pinned: true)
    ]
    let counts = TaskListHelpers.counts(tasks)
    #expect(counts.total == 2)
    #expect(counts.completed == 0)
    #expect(counts.inactive == 0)
  }

  @Test("All matching tasks completed")
  func allCompletedMatching() {
    let tasks = [
      Self.task(name: "a", completed: true, matches: true),
      Self.task(name: "b", completed: true, matches: true)
    ]
    let counts = TaskListHelpers.counts(tasks)
    #expect(counts.total == 2)
    #expect(counts.completed == 2)
    #expect(counts.inactive == 0)
  }

  @Test("Pinned-and-completed-unmatched counts as matching-or-pinned + completed")
  func pinnedCompletedUnmatched() {
    let tasks = [
      Self.task(name: "a", completed: true, matches: false, pinned: true)
    ]
    let counts = TaskListHelpers.counts(tasks)
    #expect(counts.total == 1)
    #expect(counts.completed == 1)
    #expect(counts.inactive == 0)
  }

  // MARK: - subline()

  @Test("Subline: '{completed}/{total} tasks' (no inactive)")
  func sublineBasic() {
    let counts = PhaseCounts(completed: 1, total: 2, inactive: 0)
    #expect(TaskListHelpers.subline(counts) == "1/2 tasks")
  }

  @Test("Subline appends ' · +N inactive' when inactive > 0")
  func sublineWithInactive() {
    let counts = PhaseCounts(completed: 1, total: 2, inactive: 3)
    #expect(TaskListHelpers.subline(counts) == "1/2 tasks · +3 inactive")
  }

  @Test("Subline shows 0/0 when empty")
  func sublineEmpty() {
    let counts = PhaseCounts(completed: 0, total: 0, inactive: 0)
    #expect(TaskListHelpers.subline(counts) == "0/0 tasks")
  }

  @Test("Subline includes inactive even when total == 0")
  func sublineZeroTotalWithInactive() {
    let counts = PhaseCounts(completed: 0, total: 0, inactive: 2)
    #expect(TaskListHelpers.subline(counts) == "0/0 tasks · +2 inactive")
  }

  @Test("Subline omits inactive when count == 0 (no ' · +0 inactive' suffix)")
  func sublineNoInactive() {
    let counts = PhaseCounts(completed: 2, total: 2, inactive: 0)
    #expect(TaskListHelpers.subline(counts) == "2/2 tasks")
  }
}
