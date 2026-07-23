import WidgetKit
import SwiftUI

/// Entry point for the widget extension. A bundle (rather than a bare `Widget`)
/// leaves room to add lock-screen / accessory widgets later.
@main
struct TiefstandWidgetBundle: WidgetBundle {
    var body: some Widget {
        DrynessWidget()
    }
}
