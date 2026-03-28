//
//  UmbrellaLocationManager.swift
//  Umbrella App
//
//  Handles one-shot accurate location requests from iPhone.
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class UmbrellaLocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationDescription = "Location permission not requested."
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastError: String?

    private let locationManager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        updateAuthorizationDescription()
    }

    func requestCurrentLocation() async throws -> CLLocation {
        lastError = nil
        let shouldRequestImmediately: Bool

        guard CLLocationManager.locationServicesEnabled() else {
            let error = NSError(
                domain: "UmbrellaLocationManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Location Services are turned off on this iPhone."]
            )
            lastError = error.localizedDescription
            throw error
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            shouldRequestImmediately = false
        case .restricted, .denied:
            let error = NSError(
                domain: "UmbrellaLocationManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Location permission is denied. Enable it in Settings."]
            )
            lastError = error.localizedDescription
            throw error
        case .authorizedAlways, .authorizedWhenInUse:
            shouldRequestImmediately = true
        @unknown default:
            shouldRequestImmediately = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            if shouldRequestImmediately {
                locationManager.requestLocation()
            }
        }
    }

    private func updateAuthorizationDescription() {
        let baseStatus: String

        switch locationManager.authorizationStatus {
        case .notDetermined:
            baseStatus = "Location permission not requested."
        case .restricted:
            baseStatus = "Location access is restricted."
        case .denied:
            baseStatus = "Location access is denied."
        case .authorizedAlways, .authorizedWhenInUse:
            if #available(iOS 14.0, *) {
                baseStatus = locationManager.accuracyAuthorization == .fullAccuracy
                    ? "Precise location is enabled."
                    : "Approximate location is enabled."
            } else {
                baseStatus = "Location permission granted."
            }
        @unknown default:
            baseStatus = "Location permission status unknown."
        }

        authorizationDescription = baseStatus
    }

    private func finishPendingRequest(with result: Result<CLLocation, Error>) {
        guard let pendingContinuation else { return }
        self.pendingContinuation = nil

        switch result {
        case .success(let location):
            lastLocation = location
            lastError = nil
            pendingContinuation.resume(returning: location)
        case .failure(let error):
            lastError = error.localizedDescription
            pendingContinuation.resume(throwing: error)
        }
    }
}

extension UmbrellaLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            updateAuthorizationDescription()
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if pendingContinuation != nil {
                    manager.requestLocation()
                }
            case .denied, .restricted:
                let error = NSError(
                    domain: "UmbrellaLocationManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Location permission is denied. Enable it in Settings."]
                )
                finishPendingRequest(with: .failure(error))
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                finishPendingRequest(with: .success(location))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finishPendingRequest(with: .failure(error))
        }
    }
}
