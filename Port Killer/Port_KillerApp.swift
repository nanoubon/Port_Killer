import SwiftUI
//
//  Port_KillerApp.swift
//  Port Killer
//
//  Created by nano on 27/2/2569 BE.
//



@main
struct Port_KillerApp: App {
    var body: some Scene {
        MenuBarExtra("Port Killer", systemImage: "network") {
            ContentView()
        }
        .menuBarExtraStyle(.window) // Uses a popover style window instead of a standard menu list
    }
}
