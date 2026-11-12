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
    @State private var showsFullPlayer = false
    /// True while a pushed page (like the voice picker) has hidden the tab bar.
    @State private var hidesAccessory = false
    @State private var playerGeometry = NowPlayingGeometry()

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
        .nowPlayingAccessory(playback: playback, isEnabled: !hidesAccessory)
        // A custom overlay rather than a full-screen cover: swiping down drags it like a sheet,
        // and on release it morphs back into the mini player piece by piece.
        .overlay {
            NowPlayingOverlay(playback: playback, isPresented: $showsFullPlayer, geometry: playerGeometry)
        }
        .environment(\.expandNowPlaying, ExpandNowPlayingAction { showsFullPlayer = true })
        .environment(\.nowPlayingGeometry, playerGeometry)
        .environment(\.setNowPlayingAccessoryHidden) { hidden, animated in
            guard hidesAccessory != hidden else { return }
            if animated {
                withAnimation(.snappy) { hidesAccessory = hidden }
            } else {
                hidesAccessory = hidden
            }
        }
        .task { await store.start() }
        .onAppear {
            // Only one source of sound at a time: a voice preview pauses the file, and playing a
            // file stops the preview.
            playback.onWillPlay = { [weak previewer] in previewer?.stop() }
            previewer.onWillPlay = { [weak playback] in playback?.pause() }
        }
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
