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
        WindowGroup {
            #if os(iOS)
            MobileContentView()
            #else
            ContentView()
            #endif
        }
    }
}
