import CoreLocation
import MapKit

struct DetectedStation: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
}

enum StationLocatorError: Error {
    case permissionDenied
    case locationUnavailable
    case noStationNearby
}

/// One-shot "which gas station am I at?" lookup: requests location
/// permission if needed, grabs a fix, and asks MapKit for the nearest
/// point of interest categorized as a gas station.
///
/// Create and use from the main thread; CLLocationManager delivers its
/// callbacks on the run loop it was created on.
final class StationLocator: NSObject {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func detectStation() async throws -> DetectedStation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard isAuthorized else {
            throw StationLocatorError.permissionDenied
        }

        let location = try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }

        return try await nearestStation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    /// Nearest gas station to an arbitrary coordinate (e.g. from a photo's
    /// GPS metadata). Pure MapKit search — needs no location permission.
    func nearestStation(latitude: Double, longitude: Double) async throws -> DetectedStation {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let reference = CLLocation(latitude: latitude, longitude: longitude)

        let request = MKLocalPointsOfInterestRequest(center: center, radius: 300)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        let response = try await MKLocalSearch(request: request).start()

        let nearest = response.mapItems.min { first, second in
            distance(from: reference, to: first) < distance(from: reference, to: second)
        }
        guard let nearest, let name = nearest.name else {
            throw StationLocatorError.noStationNearby
        }
        return DetectedStation(
            name: name,
            latitude: nearest.placemark.coordinate.latitude,
            longitude: nearest.placemark.coordinate.longitude
        )
    }

    private func distance(from location: CLLocation, to item: MKMapItem) -> CLLocationDistance {
        guard let itemLocation = item.placemark.location else { return .greatestFiniteMagnitude }
        return location.distance(from: itemLocation)
    }
}

extension StationLocator: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            locationContinuation?.resume(returning: location)
        } else {
            locationContinuation?.resume(throwing: StationLocatorError.locationUnavailable)
        }
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
