//
//  ContentView.swift
//  Umbrella App
//
//  Root view: ConnectView when disconnected, ControlView when connected.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = UmbrellaViewModel()

    var body: some View {
        Group {
            if viewModel.isConnected {
                ControlView(viewModel: viewModel)
            } else {
                ConnectView(viewModel: viewModel)
            }
        }
    }
}

#Preview {
    ContentView()
}
