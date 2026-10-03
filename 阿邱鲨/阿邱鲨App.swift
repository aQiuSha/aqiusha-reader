//
//  阿邱鲨App.swift
//  阿邱鲨
//
//  应用入口
//

import SwiftUI

@main
struct AQiShaApp: App {

    @StateObject private var libraryViewModel = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryViewModel)
                .preferredColorScheme(.light)
        }
    }
}
