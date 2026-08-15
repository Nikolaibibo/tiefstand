import Foundation
import AppKit
import CoreLocation
import TiefstandCore

/// Publishes a coarse position, or nothing at all.
///
/// "Nothing at all" is a first-class outcome here, not an error path. The app
/// worked without location for four releases by showing the driest gauge in
/// the country, and it keeps doing that whenever this returns `nil` — denied,
/// restricted, not yet asked, or simply not answered. Nobody is nagged, and
/// declining costs the user nothing they had before.
///
/// Reduced accuracy on purpose: the question is which of a few hundred gauges
/// is nearest, and the closest one does not change over a kilometre or two.
/// Asking for precise location to answer that would be taking more than the
/// job needs.
@MainActor
final class LocationProvider: NSObject, ObservableObject {

    @Published private(set) var coordinate: Coordinate?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        status == .authorized || status == .authorizedAlways
    }

    /// Called at launch. Only fetches when permission already exists — it never
    /// asks.
    ///
    /// Asking here does not work: this is an `LSUIElement` agent with no Dock
    /// icon and no window, and macOS will not present the authorization prompt
    /// to an app that never comes to the front. Verified — the request goes
    /// out, no dialog appears, and the status sits at `.notDetermined` forever.
    /// So the ask lives on a menu item instead, where a real click brings the
    /// app forward first. That is also the better manners: nobody gets an
    /// unexplained location prompt at login.
    func resumeIfAuthorized() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// The explicit ask, from the ••• menu. Activating first is what makes the
    /// prompt appear at all.
    func requestPermission() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Nothing this app can do — the switch lives in System Settings.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        default:
            manager.requestLocation()
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorized, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.coordinate = nil
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let value = Coordinate(longitude: location.coordinate.longitude,
                               latitude: location.coordinate.latitude)
        Task { @MainActor in self.coordinate = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // A failure is indistinguishable from "not available" as far as this
        // app is concerned — both mean: use the driest gauge instead.
        NSLog("Tiefstand: location unavailable — %@", error.localizedDescription)
        Task { @MainActor in self.coordinate = nil }
    }
}
