//
//  VocabDockApp.swift
//  VocabDock
//
//  Created by nrshima on 2026/02/22.
//

import SwiftUI
import SwiftData

@main
struct VocabDockApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: VocabularyEntry.self)
    }
}
