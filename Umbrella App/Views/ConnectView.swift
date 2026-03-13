//
//  ConnectView.swift
//  Umbrella App
//
//  View for connecting to Raspberry Pi umbrella over local HTTP.
//

import SwiftUI

struct ConnectView: View {
    @ObservedObject var viewModel: UmbrellaViewModel
    @FocusState private var hostFocused: Bool
    @FocusState private var portFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host", text: $viewModel.host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($hostFocused)

                    TextField("Port", value: $viewModel.port, format: .number)
                        .keyboardType(.numberPad)
                        .focused($portFocused)
                } header: {
                    Text("Raspberry Pi")
                } footer: {
                    Text("Enter the IP address and port of your umbrella server on the local network.")
                }

                Section {
                    connectionStateView
                    connectButton
                }
            }
            .navigationTitle("Connect")
            .onTapGesture {
                hostFocused = false
                portFocused = false
            }
        }
    }

    @ViewBuilder
    private var connectionStateView: some View {
        HStack {
            Circle()
                .fill(connectionColor)
                .frame(width: 10, height: 10)
            Text(connectionStateText)
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private var connectionStateText: String {
        switch viewModel.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        switch viewModel.connectionState {
        case .disconnected, .error:
            Button("Connect") {
                Task { await viewModel.connect() }
            }
            .disabled(viewModel.host.isEmpty || viewModel.port <= 0)
        case .connecting:
            HStack {
                ProgressView()
                Text("Connecting…")
            }
        case .connected:
            Button("Disconnect", role: .destructive) {
                viewModel.disconnect()
            }
        }
    }
}

#Preview {
    ConnectView(viewModel: UmbrellaViewModel())
}
