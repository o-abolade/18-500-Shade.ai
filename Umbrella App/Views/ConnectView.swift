//
//  ConnectView.swift
//  Umbrella App
//
//  View for connecting to Raspberry Pi umbrella over local HTTP.
//

import SwiftUI

struct ConnectView: View {
    @ObservedObject var viewModel: UmbrellaViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.19),
                    Color(red: 0.12, green: 0.23, blue: 0.35),
                    Color(red: 0.22, green: 0.39, blue: 0.49)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    statusCard
                    actionCard
                }
                .padding()
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        ConnectCard {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.16))
                        .frame(width: 68, height: 68)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.cyan)
                }

                Text("Connect to Raspberry Pi")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("The app now looks for your umbrella controller over Bluetooth Low Energy instead of IP address and port.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private var statusCard: some View {
        ConnectCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 12, height: 12)
                    Text(connectionTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                infoRow(
                    title: "Bluetooth",
                    value: viewModel.bluetoothStateDescription,
                    symbol: "bolt.horizontal.circle"
                )

                infoRow(
                    title: "Discovered Device",
                    value: viewModel.discoveredDeviceName ?? "No umbrella device found yet",
                    symbol: "dot.radiowaves.left.and.right"
                )

                infoRow(
                    title: "Connected Device",
                    value: viewModel.connectedDeviceName ?? "Not connected",
                    symbol: "cpu"
                )

                if let lastError = viewModel.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var actionCard: some View {
        ConnectCard {
            VStack(spacing: 12) {
                if viewModel.isConnected {
                    Button("Disconnect") {
                        viewModel.disconnect()
                    }
                    .buttonStyle(PrimaryConnectButtonStyle(colors: [Color.red, Color.pink]))
                } else {
                    Button(viewModel.isScanning ? "Scanning…" : "Scan for Umbrella") {
                        viewModel.scanForDevices()
                    }
                    .buttonStyle(PrimaryConnectButtonStyle(colors: [Color.cyan, Color.blue]))
                    .disabled(viewModel.isScanning)

                    Button(connectButtonTitle) {
                        Task { await viewModel.connect() }
                    }
                    .buttonStyle(PrimaryConnectButtonStyle(colors: [Color.accentColor, Color.indigo]))
                    .disabled(!viewModel.canConnect || (viewModel.discoveredDeviceName == nil && !viewModel.isScanning))
                }

                Text(viewModel.connectionSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var connectionTitle: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "Ready to Scan"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .error:
            return "Connection Error"
        }
    }

    private var connectButtonTitle: String {
        if let discoveredDeviceName = viewModel.discoveredDeviceName {
            return "Connect to \(discoveredDeviceName)"
        }

        return "Scan and Connect"
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .error:
            return .red
        }
    }

    private func infoRow(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }
}

private struct ConnectCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct PrimaryConnectButtonStyle: ButtonStyle {
    let colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct ConnectView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectView(viewModel: UmbrellaViewModel())
    }
}
