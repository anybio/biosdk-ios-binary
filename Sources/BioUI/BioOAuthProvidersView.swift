//
//  BioOAuthProvidersView.swift
//  BioSDK / BioUI
//
//  Reusable list view for connecting/disconnecting third-party OAuth providers
//  (Fitbit, Dexcom, Whoop, Oura, Withings, Polar, etc.). Caller supplies xuserId
//  + organizationId so the view works in both developer-key flows (KitchenSink)
//  and platform-mode enrollment flows (AnyBio).
//
//  Renders a pre-handoff interstitial sheet before launching the OAuth provider's
//  consent flow, naming the destination organization + program in the platform's
//  voice (defense-in-depth even when the provider's consent screen names the
//  right brand).
//
//  Composes alongside BioHealthKitSyncView — caller arranges them in the
//  surrounding List/Form to control layout.
//

import SwiftUI
import AuthenticationServices
import BioSDK

// MARK: - BioOAuthProvidersView

/// A self-contained list of available OAuth providers with connect/disconnect
/// actions per row. Pre-handoff interstitial confirms the destination
/// organization before launching the provider consent flow.
///
/// Usage:
/// ```swift
/// BioOAuthProvidersView(
///     sdk: sdk,
///     xuserId: enrollment.xuserId,
///     organizationId: enrollment.orgId,
///     organizationDisplayName: "Kaiser",
///     programDisplayName: "Sleep Pilot"
/// )
/// ```
public struct BioOAuthProvidersView: View {
    private let sdk: BioSDKClient
    private let xuserId: String
    private let organizationId: Int
    private let organizationDisplayName: String?
    private let programDisplayName: String?

    @State private var providers: [OAuthProvider] = []
    @State private var connectionStatuses: [String: Bool] = [:]
    @State private var isLoading = true
    @State private var connectingProvider: String?
    @State private var pendingProvider: PendingProviderHandoff?
    @State private var errorMessage: String?
    @State private var showError = false

    private let presentationContextProvider = WebAuthPresentationContextProvider()

    public init(
        sdk: BioSDKClient,
        xuserId: String,
        organizationId: Int,
        organizationDisplayName: String? = nil,
        programDisplayName: String? = nil
    ) {
        self.sdk = sdk
        self.xuserId = xuserId
        self.organizationId = organizationId
        self.organizationDisplayName = organizationDisplayName
        self.programDisplayName = programDisplayName
    }

    public var body: some View {
        Group {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading providers…")
                    Spacer()
                }
                .padding()
            } else if providers.isEmpty {
                Text("No providers are currently available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(providers, id: \.slug) { provider in
                    BioOAuthProviderRow(
                        provider: provider,
                        isConnected: connectionStatuses[provider.slug] ?? false,
                        isConnecting: connectingProvider == provider.slug,
                        onConnect: { pendingProvider = PendingProviderHandoff(provider: provider) },
                        onDisconnect: { disconnect(provider) }
                    )
                }
            }
        }
        .sheet(item: $pendingProvider) { handoff in
            BioOAuthInterstitialSheet(
                provider: handoff.provider,
                organizationDisplayName: organizationDisplayName,
                programDisplayName: programDisplayName,
                onContinue: {
                    pendingProvider = nil
                    connect(handoff.provider)
                },
                onCancel: {
                    pendingProvider = nil
                }
            )
        }
        .alert("Connection Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await loadProviders()
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadProviders() async {
        // 1. Fetch available providers from BE — may fail if the JWT lacks
        //    Read scope; fall back to a curated list of common providers.
        do {
            try await sdk.oauth?.refreshAvailableProviders()
            if let configs = sdk.oauth?.availableProviders {
                providers = configs.map { $0.asProvider }
            }
        } catch {
            providers = [.fitbit, .dexcom, .whoop, .oura, .withings, .polar]
        }

        // 2. Fetch per-xuser connection statuses.
        do {
            try await sdk.oauth?.refreshConnectionStatuses(
                organizationId: organizationId,
                xuserId: xuserId
            )
        } catch {
            // Non-fatal — providers list still renders; connection state stays "Not connected".
        }

        for provider in providers {
            connectionStatuses[provider.slug] = sdk.isOAuthProviderConnected(provider.slug)
        }

        isLoading = false
    }

    private func connect(_ provider: OAuthProvider) {
        connectingProvider = provider.slug
        Task { @MainActor in
            defer { connectingProvider = nil }
            do {
                try await sdk.connectOAuthProvider(
                    provider.slug,
                    xuserId: xuserId,
                    presentationContextProvider: presentationContextProvider
                )
                connectionStatuses[provider.slug] = true
            } catch let error as OAuthError {
                if case .userCancelled = error { return }
                showErrorAlert(error.localizedDescription)
            } catch {
                showErrorAlert("Failed to connect: \(error.localizedDescription)")
            }
        }
    }

    private func disconnect(_ provider: OAuthProvider) {
        sdk.disconnectOAuthProvider(provider.slug)
        connectionStatuses[provider.slug] = false
    }

    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Provider Row

private struct BioOAuthProviderRow: View {
    let provider: OAuthProvider
    let isConnected: Bool
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline)
                Text(isConnected ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundColor(isConnected ? .green : .secondary)
            }

            Spacer()

            if isConnecting {
                ProgressView().progressViewStyle(.circular)
            } else if isConnected {
                Button("Disconnect", action: onDisconnect)
                    .font(.caption)
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
            } else {
                Button("Connect", action: onConnect)
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pre-Handoff Interstitial

private struct BioOAuthInterstitialSheet: View {
    let provider: OAuthProvider
    let organizationDisplayName: String?
    let programDisplayName: String?
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connect \(provider.displayName)")
                        .font(.title2)
                        .bold()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(destinationLine)
                            .font(.body)
                        ForEach(dataClasses(for: provider.slug), id: \.self) { dataClass in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(dataClass)
                            }
                            .font(.body)
                        }
                    }

                    if let programDisplayName, !programDisplayName.isEmpty {
                        Text("\(orgLabel) will use this data for your enrolled program: \(programDisplayName).")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(action: onContinue) {
                        Text("Continue to \(provider.displayName)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Cancel", action: onCancel)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var orgLabel: String {
        organizationDisplayName?.isEmpty == false ? organizationDisplayName! : "Your provider"
    }

    private var destinationLine: String {
        "You're sharing the following data with \(orgLabel) via AnyBio:"
    }
}

// MARK: - Data class lookup (templated v1)

/// Templated data-class disclosure per provider slug. Keep aligned with the
/// scopes configured in `oauth_provider_configs` server-side. Unknown slugs
/// fall back to a generic phrase so the interstitial still displays.
private func dataClasses(for slug: String) -> [String] {
    switch slug.lowercased() {
    case "fitbit":
        return ["Steps", "Heart rate", "Sleep", "Activity"]
    case "google_health", "google-health", "googlehealth":
        return ["Steps", "Heart rate", "Sleep", "Activity", "Body composition"]
    case "dexcom":
        return ["Continuous glucose readings"]
    case "whoop":
        return ["Heart rate", "Recovery", "Strain", "Sleep"]
    case "oura":
        return ["Sleep", "Activity", "Readiness", "Heart rate"]
    case "withings":
        return ["Weight", "Blood pressure", "Sleep", "Activity"]
    case "polar":
        return ["Heart rate", "Activity", "Workouts"]
    case "epic":
        return ["Clinical records", "Vitals", "Lab results"]
    case "medplum":
        return ["Clinical observations", "Conditions", "Medications"]
    default:
        return ["Your activity and biometric data"]
    }
}

// MARK: - OAuthProvider sheet(item:) wrapper

/// `sheet(item:)` requires `Identifiable`. Rather than retroactively conform
/// `OAuthProvider` (which lives in BioSDK), wrap the slug in a lightweight
/// `Identifiable` shell when presenting.
private struct PendingProviderHandoff: Identifiable {
    let provider: OAuthProvider
    var id: String { provider.slug }
}

// MARK: - Presentation context

private final class WebAuthPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
