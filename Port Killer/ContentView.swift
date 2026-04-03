import SwiftUI
//
//  ContentView.swift
//  Port Killer
//
//  Created by nano on 27/2/2569 BE.
//


struct ContentView: View {
    @StateObject private var viewModel = PortViewModel()
    @State private var searchText = ""
    @State private var showHelp = false // Controls the display of the Help window
    
    var filteredPorts: [PortItem] {
        if searchText.isEmpty {
            return viewModel.ports
        } else {
            return viewModel.ports.filter {
                $0.processName.localizedCaseInsensitiveContains(searchText) ||
                $0.port.localizedCaseInsensitiveContains(searchText) ||
                $0.pid.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Active Ports")
                    .font(.headline)
                Spacer()
                
                // Help Button
                Button(action: {
                    showHelp.toggle()
                }) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help("How to use Port Killer")
                
                // Refresh Button
                Button(action: {
                    viewModel.fetchActivePorts()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh Port List")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search port, process, or PID...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // List of Ports
            if filteredPorts.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty ? "No active listening ports found." : "No matching ports.")
                        .foregroundColor(.secondary)
                    
                    #if DEBUG
                    if searchText.isEmpty {
                        Text("Debug: \(viewModel.debugMessage)")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    #endif
                        
                    Spacer()
                }
                .frame(minHeight: 150)
            } else {
                List(filteredPorts) { portItem in
                    HStack {
                        // App Icon
                        if let icon = portItem.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "terminal")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Port: \(portItem.port)")
                                .font(.system(.body, design: .monospaced))
                                .bold()
                            Text("\(portItem.processName) (PID: \(portItem.pid))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Kill Button
                        Button(action: {
                            viewModel.killProcess(pid: portItem.pid)
                        }) {
                            Text("Kill")
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Kill process \(portItem.processName)")
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 200, maxHeight: 400)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 350, height: 400) // Fixed size for consistency in Menu
        .onAppear {
            viewModel.fetchActivePorts()
        }
        // Help Sheet
        .sheet(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How to use Port Killer")
                    .font(.title2)
                    .bold()
                
                Text("**List of Ports:** The app automatically shows ports with a `LISTEN` TCP state.")
                Text("**Search:** Type a port number (e.g., 8080) or app name (e.g., node) to filter.")
                Text("**Kill:** Clicking the red 'Kill' button will forcefully terminate the process (`kill -9 PID`) immediately.")
                    .foregroundColor(.red)
                
                Text("**Troubleshooting:**\nIf ports aren't showing up, ensure that the Xcode project has **App Sandbox** disabled in the *Signing & Capabilities* tab.\n\nWithout it, the shell commands `lsof` and `kill` will be blocked by macOS security.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                
                HStack {
                    Spacer()
                    Button("Close") {
                        showHelp = false
                    }
                    .padding(.top, 16)
                    Spacer()
                }
            }
            .padding()
            .frame(width: 300, height: 350)
        }
    }
}

#Preview {
    ContentView()
}
