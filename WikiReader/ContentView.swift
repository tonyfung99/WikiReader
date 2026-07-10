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
    @State private var showError = false

    var body: some View {
        Group {
            if let root = rootURL {
                MainTabs(root: root, store: store) { showPicker = true }
                    .id(root)
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
        .onChange(of: store.errorMessage) { _, newValue in
            showError = (newValue != nil)
        }
        .alert("Vault Error", isPresented: $showError) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private enum MainTab: Hashable {
    case home, files, ask, graph
}

private struct MainTabs: View {
    let root: URL
    let store: VaultStore
    var onChangeVault: () -> Void

    @State private var index: VaultIndex
    @State private var selection: MainTab = .home
    @State private var pendingQuestion: String?

    init(root: URL, store: VaultStore, onChangeVault: @escaping () -> Void) {
        self.root = root
        self.store = store
        self.onChangeVault = onChangeVault
        _index = State(initialValue: VaultIndex(root: root))
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(root: root)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(MainTab.home)

            NavigationStack {
                FilesTabView(root: root, title: store.displayName ?? "Vault") { question in
                    pendingQuestion = question
                    selection = .ask
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Change Vault", systemImage: "folder.badge.gearshape", action: onChangeVault)
                    }
                }
            }
            .tabItem { Label("Files", systemImage: "folder") }
            .tag(MainTab.files)

            NavigationStack {
                AskWikiView(root: root, pendingQuestion: $pendingQuestion)
                    .navigationTitle("Ask")
            }
            .tabItem { Label("Ask", systemImage: "questionmark.bubble") }
            .tag(MainTab.ask)

            NavigationStack {
                GraphScreen(root: root)
                    .navigationTitle("Graph")
            }
            .tabItem { Label("Graph", systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(MainTab.graph)
        }
        .environment(index)
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

#Preview("Root") {
    ContentView()
}

#Preview("Welcome") {
    WelcomeView {}
}
