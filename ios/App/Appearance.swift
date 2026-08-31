import SwiftUI

/// Where the digits sit in the app's own display.
///
/// iOS has no floating overlay, so unlike the macOS version this only positions
/// the digits inside this app's window rather than on top of the system.
enum DigitCorner: String, CaseIterable, Identifiable {
    case topRight, topLeft, bottomLeft, bottomRight, center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .center: return "Center"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topRight: return .topTrailing
        case .topLeft: return .topLeading
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        case .center: return .center
        }
    }
}

enum DigitSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Font size as a fraction of the shorter screen edge. The macOS build scales
    /// off screen height, but a phone held upright is tall and narrow, so height
    /// there would overflow the width.
    var fontScale: CGFloat {
        switch self {
        case .small: return 0.14
        case .medium: return 0.22
        case .large: return 0.32
        }
    }
}

enum DigitTransparency: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Matches the macOS scale, so the two apps look the same at a given setting.
    var opacity: CGFloat {
        switch self {
        case .low: return 0.70
        case .medium: return 0.45
        case .high: return 0.25
        }
    }
}

/// Keys for the persisted appearance settings.
///
/// The settings are read with `@AppStorage` directly in the views that use them.
/// Wrapping them in an `ObservableObject` looks tidier but does not work:
/// `@AppStorage` is a `DynamicProperty` that depends on a view's update cycle, so
/// inside an observable object it stores values without ever publishing changes.
enum AppearanceKey {
    static let corner = "digitCorner"
    static let size = "digitSize"
    static let transparency = "digitTransparency"
}
