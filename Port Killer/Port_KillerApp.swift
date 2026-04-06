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
    @StateObject private var proStore = ProPurchaseManager()
    @StateObject private var appRouter = AppRouter()

    var body: some Scene {
        Window("Port Killer", id: "main") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(proStore)
                .environmentObject(appRouter)
        }
        .defaultSize(width: 980, height: 740)

        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(viewModel)
                .environmentObject(proStore)
                .environmentObject(appRouter)
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
