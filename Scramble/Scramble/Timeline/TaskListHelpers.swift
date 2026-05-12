import Foundation

/// Phase-row task counts. `total` is the count of tasks classified as
/// matching-or-pinned (i.e., `currentlyMatchesRules || pinnedByUser`).
/// `completed` is the subset of those that are also `isCompleted`.
/// `inactive` is the count of unmatched-non-pinned tasks regardless of
/// completion state, surfaced separately as ` · +N inactive` in the subline.
struct PhaseCounts: Equatable, Sendable {
  let completed: Int
  let total: Int
  let inactive: Int
}

/// Pure helpers used by `TaskListSection` (sort) and `PhaseRow` (subline).
@MainActor
enum TaskListHelpers {

  /// Sort tasks per Req 5.1 + 5.2.
  ///
  /// Buckets in output order:
  /// 1. Matching-or-pinned + incomplete
  /// 2. Matching-or-pinned + completed
  /// 3. Unmatched-non-pinned + incomplete
  /// 4. Unmatched-non-pinned + completed
  ///
  /// Within each bucket the name comparison uses
  /// `localizedCaseInsensitiveCompare` so mixed-case and non-ASCII names
  /// sort by user-visible locale rules.
  static func sorted(_ tasks: [TripTask]) -> [TripTask] {
    tasks.sorted { lhs, rhs in
      let lb = bucket(lhs)
      let rb = bucket(rhs)
      if lb != rb { return lb < rb }
      // Same bucket — compare by name, case-insensitive, locale-aware.
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  /// Compute matching/completed/inactive counts for a phase's task list.
  static func counts(_ tasks: [TripTask]) -> PhaseCounts {
    var total = 0
    var completed = 0
    var inactive = 0
    for task in tasks {
      if task.currentlyMatchesRules || task.pinnedByUser {
        total += 1
        if task.isCompleted { completed += 1 }
      } else {
        inactive += 1
      }
    }
    return PhaseCounts(completed: completed, total: total, inactive: inactive)
  }

  /// Render the phase header subline per Req 5.3.
  static func subline(_ counts: PhaseCounts) -> String {
    let base = "\(counts.completed)/\(counts.total) tasks"
    guard counts.inactive > 0 else { return base }
    return "\(base) · +\(counts.inactive) inactive"
  }

  // MARK: - Private

  /// Bucket index used by `sorted`. Lower index sorts earlier.
  /// - 0: matching-or-pinned, incomplete
  /// - 1: matching-or-pinned, completed
  /// - 2: unmatched-non-pinned, incomplete
  /// - 3: unmatched-non-pinned, completed
  private static func bucket(_ task: TripTask) -> Int {
    let matchingOrPinned = task.currentlyMatchesRules || task.pinnedByUser
    switch (matchingOrPinned, task.isCompleted) {
    case (true, false): return 0
    case (true, true): return 1
    case (false, false): return 2
    case (false, true): return 3
    }
  }
}
