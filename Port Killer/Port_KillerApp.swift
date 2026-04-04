import SwiftUI
//
//  Port_KillerApp.swift
//  Port Killer
//
//  Created by nano on 27/2/2569 BE.
//



@main
struct Port_KillerApp: App {
    @StateObject private var viewModel = PortViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(viewModel)
        }

        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(viewModel)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityLabel("Port Killer")
        }
        .menuBarExtraStyle(.window) // Uses a popover style window instead of a standard menu list
    }
}
