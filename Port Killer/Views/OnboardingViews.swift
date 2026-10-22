import AppKit
import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @State private var page = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "Instantly Detect Active Ports",
            subtitle: "Eliminate the lsof guesswork. Real-time visibility into every listening socket on your machine.",
            note: "Step 01 / 03"
        ),
        OnboardingStep(
            title: "Kill with Precision",
            subtitle: "See live PIDs, monitor usage, and terminate exactly the process you want with a single click.",
            note: "Step 02 / 03"
        ),
        OnboardingStep(
            title: "Unlock the Professional Layer",
            subtitle: "Pin common ports, automate guardrails, and keep your environment surgically clean.",
            note: "Step 03 / 03"
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.pkBackground, Color.pkBackground, Color.pkPrimary.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Text("PORT KILLER")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(Color.pkText)
                    Spacer()
                }
                .padding(.top, 18)

                Text(steps[page].note)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.pkPrimary.opacity(0.08))
                    )

                VStack(spacing: 14) {
                    Text(steps[page].title)
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(Color.pkText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 680)

                    Text(steps[page].subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.pkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 760)
                }

                CardShell(fill: Color.pkCard, radius: 26) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("12 Ports Listening")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.pkText)
                            VStack(alignment: .leading, spacing: 8) {
                                OnboardingBullet(symbol: "waveform.path.ecg") {
                                    Text("Track live sockets with one glance")
                                }
                                OnboardingBullet(symbol: "bolt.fill") {
                                    Text("Kill noisy processes without context switching")
                                }
                                OnboardingBullet(symbol: "star.fill") {
                                    Text("Save the ports you use every day")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        CardShell(fill: Color.pkElevated, radius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("SYSTEM SNAPSHOT")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.pkMuted)
                                VStack(spacing: 8) {
                                    ForEach(viewModel.visiblePorts.prefix(3)) { port in
                                        HStack {
                                            Text(port.port)
                                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                .foregroundStyle(Color.pkPrimary)
                                            Spacer()
                                            Text(port.processName)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Color.pkText)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 300)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            page = max(0, page - 1)
                        }
                    } label: {
                        Text("Skip")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button {
                        if page < steps.count - 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                page += 1
                            }
                        } else {
                            viewModel.completeOnboarding()
                        }
                    } label: {
                        Text(page < steps.count - 1 ? "Next Step" : "Get Started")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }

                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(index == page ? Color.pkPrimary : Color.pkStroke)
                            .frame(width: index == page ? 32 : 20, height: 4)
                    }
                }
                .padding(.top, 4)
            }
            .padding(26)
            .frame(maxWidth: 980)
        }
    }
}

struct OnboardingStep {
    let title: String
    let subtitle: String
    let note: String
}

struct OnboardingBullet<Content: View>: View {
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.pkSecondary)
                .frame(width: 16)
            content()
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.pkText)
            Spacer(minLength: 0)
        }
    }
}
