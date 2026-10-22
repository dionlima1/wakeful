import SwiftUI

struct ProView: View {
    @State private var store = ProStore.shared

    private let features: [(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        ("sparkles", "AI agent mode", "Stays awake while Claude Code, Codex, Gemini or any agent you add is working."),
        ("wand.and.stars", "Automatic triggers", "External display, power adapter, Wi‑Fi, apps, video calls and schedules."),
        ("terminal", "Processes and apps", "Stay awake until a command, script or app finishes."),
        ("laptopcomputer", "Lid closed", "Keep working with the lid closed while plugged in."),
        ("chart.bar.xaxis", "History", "See how long your Mac stayed awake, and why."),
    ]

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: store.isPro ? "checkmark.seal.fill" : "star.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text(store.isPro ? "Wakeful Pro is unlocked" : "Wakeful Pro")
                        .font(.title2.weight(.semibold))
                    Text(store.isPro ? "Thank you for supporting an independent developer!" : "One purchase. No subscription. Shared with your family.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                ForEach(features, id: \.symbol) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: feature.symbol)
                            .frame(width: 22)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.headline)
                            Text(feature.detail).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !store.isPro {
                Section {
                    HStack {
                        Button("Restore Purchases") { Task { await store.restore() } }
                        Spacer()
                        purchaseButton
                    }
                    switch store.purchaseState {
                    case .pending:
                        Text("Your purchase is waiting for approval.").foregroundStyle(.secondary)
                    case .failed(let message):
                        Text(message).foregroundStyle(.red)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { if store.product == nil { await store.loadProduct() } }
    }

    @ViewBuilder
    private var purchaseButton: some View {
        if store.purchaseState == .purchasing {
            ProgressView().controlSize(.small)
        } else {
            Button {
                Task { await store.purchase() }
            } label: {
                if let price = store.product?.displayPrice {
                    Text("Unlock for \(price)")
                } else {
                    Text("Unlock Pro")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
