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
  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(\.theme, .midnightAtlas)
    }
    .modelContainer(ModelStore.shared)
  }
}
