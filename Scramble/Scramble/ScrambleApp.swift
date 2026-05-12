//
//  ScrambleApp.swift
//  Scramble
//
//  Created by Arjen Schwarz on 10/5/2026.
//

import SwiftData
import SwiftUI
import os

@main
struct ScrambleApp: App {
  init() {
    #if DEBUG
      UITestSeed.applyIfRequested(to: ModelStore.shared)
    #endif
    // Cold-launch scan per AC 5.4. Errors surface in Console; there is no
    // UI mounted yet to show a toast against.
    do {
      _ = try RulesEngineRunner(context: ModelStore.shared.mainContext).runForAllNonPastTrips()
    } catch {
      modelLogger.error(
        "[RulesEngine.cold-launch-failed] error=\(String(describing: error), privacy: .public)"
      )
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(\.theme, .midnightAtlas)
    }
    .modelContainer(ModelStore.shared)
  }
}
