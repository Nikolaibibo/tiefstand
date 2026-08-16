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

    /// Called when a fix arrives.
    ///
    /// A fix lands seconds *after* permission is granted, long after the
    /// refresh that triggered the request has finished. Without this the local
    /// gauge would keep showing the driest station until the next scheduled
    /// poll — up to two hours — and granting permission would look like it had
    /// done nothing.
    var onFix: (() -> Void)?

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

    /// The explicit ask, from the ••• menu.
    ///
    /// The activation-policy dance is the load-bearing part. As an
    /// `LSUIElement` agent the app runs as `.accessory`: no Dock icon, no
    /// menu, and — the part that matters — it cannot truly become the active
    /// application. macOS will not put an authorization prompt in front of an
    /// app that cannot come forward, so the request simply evaporates:
    /// no dialog, and `authorizationStatus` stays `.notDetermined` forever.
    ///
    /// Switching to `.regular` for the duration makes it a foreground app long
    /// enough to be asked. It costs a Dock icon for a few seconds, which is a
    /// fair price for a prompt that otherwise never appears.
    func requestPermission() {
        let wasAccessory = NSApplication.shared.activationPolicy() == .accessory
        if wasAccessory { NSApplication.shared.setActivationPolicy(.regular) }
        NSApplication.shared.activate(ignoringOtherApps: true)

        if wasAccessory {
            // Back to an agent once the prompt has been answered — or after a
            // grace period, in case it is dismissed without an answer.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }


        switch status {
        case .notDetermined:
            // Ask properly — this is the correct API call and it is what works
            // on a normal app.
            manager.requestWhenInUseAuthorization()
            // …but on this app it reliably shows nothing. Verified at length:
            // the menu fires, the policy switches to .regular, `isActive` is
            // true, the request goes out — and macOS never presents a dialog
            // or records a decision. So if the status has not moved shortly
            // after, take the user to the switch instead of leaving them
            // staring at a menu item that did nothing.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if self.status == .notDetermined { Self.openSettings() }
            }
        case .denied, .restricted:
            Self.openSettings()
        default:
            manager.requestLocation()
        }
    }

    /// Privacy & Security → Location Services.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
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
        Task { @MainActor in
            self.coordinate = value
            self.onFix?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // A failure is indistinguishable from "not available" as far as this
        // app is concerned — both mean: use the driest gauge instead.
        NSLog("Tiefstand: location unavailable — %@", error.localizedDescription)
        Task { @MainActor in self.coordinate = nil }
    }
}
