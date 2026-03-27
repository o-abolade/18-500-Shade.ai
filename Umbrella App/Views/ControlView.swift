//
//  ControlView.swift
//  Umbrella App
//
//  View for controlling the Raspberry Pi umbrella.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ControlView: View {
    @ObservedObject var viewModel: UmbrellaViewModel

    private let statusColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.11, blue: 0.20),
                    Color(red: 0.10, green: 0.22, blue: 0.38),
                    Color(red: 0.18, green: 0.39, blue: 0.54)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    overviewSection
                    locationSection
                    directionControls
                    stopButton
                    modeSection
                }
                .padding()
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Control")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.isUsingDemoMode {
                ToolbarItem(placement: .primaryAction) {
                    Button("Disconnect") {
                        Task { @MainActor in
                            await Task.yield()
                            viewModel.disconnect()
                        }
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Umbrella Controller")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Bluetooth control with live phone location sharing")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Spacer()

                    connectionBadge
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Position")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        Text(positionValue)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan, Color.mint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: proxy.size.width * positionProgress)
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 10, height: 10)
            Text(connectionText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    private var overviewSection: some View {
        LazyVGrid(columns: statusColumns, spacing: 12) {
            statCard(
                title: "Mode",
                value: viewModel.status?.mode ?? "Manual",
                symbol: "dial.medium.fill",
                tint: .cyan
            )
            statCard(
                title: "Movement",
                value: (viewModel.status?.moving ?? false) ? "Active" : "Idle",
                symbol: "arrow.up.and.down.and.arrow.left.and.right",
                tint: .mint
            )
            statCard(
                title: "Connection",
                value: connectionText,
                symbol: "dot.radiowaves.left.and.right",
                tint: .green
            )
            statCard(
                title: "Device",
                value: viewModel.preferredDeviceName,
                symbol: "cpu",
                tint: .orange
            )
        }
    }

    private func statCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 40, height: 40)

                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var directionControls: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Directional Control",
                    subtitle: "Tap to adjust the umbrella position"
                )

                VStack(spacing: 14) {
                    HStack {
                        Spacer()
                        directionButton(symbol: "arrow.up", label: "Up", direction: "up")
                        Spacer()
                    }

                    HStack(spacing: 18) {
                        directionButton(symbol: "arrow.left", label: "Left", direction: "left")

                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.78)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)
                                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)

                            VStack(spacing: 6) {
                                Image(systemName: "dot.radiowaves.up.forward")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.cyan)
                                Text("Drive")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        directionButton(symbol: "arrow.right", label: "Right", direction: "right")
                    }

                    HStack {
                        Spacer()
                        directionButton(symbol: "arrow.down", label: "Down", direction: "down")
                        Spacer()
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Phone Location",
                    subtitle: "Capture the iPhone's current coordinates and send them to the Raspberry Pi"
                )

                VStack(alignment: .leading, spacing: 10) {
                    locationInfoRow(
                        title: "Permission",
                        value: viewModel.locationPermissionDescription,
                        symbol: "location.circle"
                    )
                    locationInfoRow(
                        title: "Latest Coordinates",
                        value: viewModel.locationSummary,
                        symbol: "mappin.and.ellipse"
                    )
                }

                Button {
                    Task { await viewModel.sendCurrentLocation() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill")
                        Text(viewModel.isSendingLocation ? "Requesting Location..." : "Send Current Location")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSendingLocation || !viewModel.isConnected)
            }
        }
    }

    private var stopButton: some View {
        Button {
            Task { await viewModel.stop() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "stop.fill")
                Text("Emergency Stop")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color.red, Color.pink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.red.opacity(0.28), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var modeSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Operating Mode",
                    subtitle: "Switch between manual and automatic response"
                )

                HStack(spacing: 12) {
                    modeButton("Manual")
                    modeButton("Auto")
                }
            }
        }
    }

    private func modeButton(_ mode: String) -> some View {
        let isSelected = (viewModel.status?.mode ?? "").caseInsensitiveCompare(mode) == .orderedSame

        return Button {
            Task { await viewModel.setMode(mode) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(mode)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func directionButton(symbol: String, label: String, direction: String) -> some View {
        Button {
            viewModel.move(direction: direction)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 88, height: 88)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(Circle())
            .shadow(color: Color.accentColor.opacity(0.28), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func locationInfoRow(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var positionValue: String {
        if let position = viewModel.status?.position {
            return "\(position)%"
        }

        return "--"
    }

    private var positionProgress: CGFloat {
        CGFloat(viewModel.status?.position ?? 0) / 100
    }

    private var connectionText: String {
        switch viewModel.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .error:
            return "Error"
        case .disconnected:
            return "Offline"
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }
}

private struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
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

struct ControlView_Previews: PreviewProvider {
    static var previews: some View {
        ControlView(viewModel: UmbrellaViewModel())
    }
}
