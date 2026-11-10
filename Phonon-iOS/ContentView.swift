//
//  ContentView.swift
//  Phonon-iOS
//
//  Created by DNA on 10/23/26.
//  
//

import SwiftUI

/// App tabs. On iOS 26 the tab bar and navigation chrome adopt Liquid Glass automatically.
struct ContentView: View {
    enum AppTab: Hashable {
        case create, library, settings
    }

    @State private var store = ModelStore()
    @State private var exporter = ExportController()
    @State private var library = ExportLibrary()
    @State private var playback = PlaybackController()
    @State private var previewer = VoicePreviewer()
    @State private var selection: AppTab = .create

    var body: some View {
        TabView(selection: $selection) {
            Tab("Write", systemImage: "square.and.pencil", value: AppTab.create) {
                CreateView(
                    store: store,
                    exporter: exporter,
                    playback: playback,
                    library: library,
                    previewer: previewer,
                    openSettings: { selection = .settings },
                    openLibrary: { selection = .library }
                )
            }
            Tab("Library", systemImage: "waveform", value: AppTab.library) {
                LibraryView(library: library, playback: playback)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(store: store, exporter: exporter, previewer: previewer, playback: playback)
            }
        }
        .task { await store.start() }
        .confirmationDialog(
            "Download over a metered connection?",
            isPresented: $store.needsCellularConfirmation,
            titleVisibility: .visible
        ) {
            Button("Download Now") { store.download(allowCellular: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You are not on Wi-Fi. The voice model is \(store.downloadSizeText).")
        }
    }
}

#Preview {
    ContentView()
}
