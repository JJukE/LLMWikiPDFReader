//
//  LLMWikiPDFReaderApp.swift
//  LLMWikiPDFReader
//
//  Created by 박상준 on 2026.06.07.
//

import SwiftUI

@main
struct LLMWikiPDFReaderApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("Reader") {
                Button("Find") {
                    NotificationCenter.default.post(name: .findShortcut, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }
        #else
        WindowGroup {
            #if os(iOS)
            MobileContentView()
            #else
            ContentView()
            #endif
        }
        #endif
    }
}

#if os(macOS)
extension Notification.Name {
    static let findShortcut = Notification.Name("findShortcut")
}
#endif
