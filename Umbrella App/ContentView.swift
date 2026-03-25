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
        NavigationStack {
            Group {
                if viewModel.isConnected {
                    ControlView(viewModel: viewModel)
                } else {
                    ConnectView(viewModel: viewModel)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
