//
//  ControlView.swift
//  Umbrella App
//
//  View for controlling the Raspberry Pi umbrella.
//

import SwiftUI

struct ControlView: View {
    @ObservedObject var viewModel: UmbrellaViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusSection
                    directionControls
                    stopButton
                    modeSection
                }
                .padding()
            }
            .navigationTitle("Control")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect") {
                        viewModel.disconnect()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            if let status = viewModel.status {
                HStack(spacing: 16) {
                    statusRow("Position", value: status.position.map { "\($0)" } ?? "—")
                    statusRow("Mode", value: status.mode ?? "—")
                    statusRow("Moving", value: (status.moving ?? false) ? "Yes" : "No")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text("Polling…")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private var directionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move")
                .font(.headline)
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    moveButton("Up", direction: "up")
                    Spacer()
                }
                HStack {
                    moveButton("Left", direction: "left")
                    Spacer()
                    moveButton("Right", direction: "right")
                }
                HStack {
                    Spacer()
                    moveButton("Down", direction: "down")
                    Spacer()
                }
            }
        }
    }

    private func moveButton(_ title: String, direction: String) -> some View {
        Button {
            viewModel.move(direction: direction)
        } label: {
            Text(title)
                .frame(minWidth: 80, minHeight: 44)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var stopButton: some View {
        Button {
            Task { await viewModel.stop() }
        } label: {
            Label("Stop", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.headline)
            HStack(spacing: 12) {
                modeButton("Manual")
                modeButton("Auto")
            }
        }
    }

    private func modeButton(_ mode: String) -> some View {
        Button {
            Task { await viewModel.setMode(mode) }
        } label: {
            Text(mode)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ControlView(viewModel: UmbrellaViewModel())
}
