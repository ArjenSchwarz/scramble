//
//  ScrambleApp.swift
//  Scramble
//
//  Created by Arjen Schwarz on 10/5/2026.
//

import SwiftData
import SwiftUI

@main
struct ScrambleApp: App {
  init() {
    #if DEBUG
      UITestSeed.applyIfRequested(to: ModelStore.shared)
    #endif
    _ = try? RulesEngineRunner(context: ModelStore.shared.mainContext).runForAllNonPastTrips()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(\.theme, .midnightAtlas)
    }
    .modelContainer(ModelStore.shared)
  }
}
