//
//  ContentView.swift
//  WikiReader
//
//  Created by Tony Fung on 24/5/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var store = VaultStore()
    @State private var rootURL: URL?
    @State private var showPicker = false

    var body: some View {
        Group {
            if let root = rootURL {
                MainTabs(root: root, store: store) { showPicker = true }
            } else if store.hasVault {
                ProgressView("Opening vault…")
                    .task { rootURL = store.beginBrowsing() }
            } else {
                WelcomeView { showPicker = true }
            }
        }
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in
                store.setVault(url: url)
                rootURL = store.beginBrowsing()
            }
            .ignoresSafeArea()
        }
        .alert(
            "Vault Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct MainTabs: View {
    let root: URL
    let store: VaultStore
    var onChangeVault: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                VaultBrowserView(directory: root, title: store.displayName ?? "Vault")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Change Vault", systemImage: "folder.badge.gearshape", action: onChangeVault)
                        }
                    }
            }
            .tabItem { Label("Files", systemImage: "folder") }

            NavigationStack {
                GraphScreen(root: root)
                    .navigationTitle("Graph")
            }
            .tabItem { Label("Graph", systemImage: "point.3.connected.trianglepath.dotted") }
        }
    }
}

private struct WelcomeView: View {
    var onChoose: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("WikiReader", systemImage: "books.vertical")
        } description: {
            Text("Choose your iCloud Drive vault folder to browse and read your clipped notes.")
        } actions: {
            Button("Choose Vault Folder", action: onChoose)
                .buttonStyle(.borderedProminent)
        }
    }
}
