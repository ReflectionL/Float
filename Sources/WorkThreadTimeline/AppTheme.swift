import AppKit
import SwiftUI

/// Float's design tokens, following the same language as Zulip Mac: neutral
/// surfaces in fixed steps, one indigo accent, three font weights, four radii
/// and a small set of motion curves. Views use these instead of literal values.
enum AppTheme {
    enum Metrics {
        static let columnWidth: CGFloat = 316
        static let columnSpacing: CGFloat = 8
        static let columnInset: CGFloat = 24
        /// Space between NOW, NOTE and TIMELINE in a column.
        static let sectionGap: CGFloat = 22
        /// The time column in front of each timeline entry.
        static let timelineTimeWidth: CGFloat = 44
        static let workspaceInset: CGFloat = 16
        static let minimumWindowWidth: CGFloat = 760
        static let minimumWindowHeight: CGFloat = 520
        static let hairline: CGFloat = 1
    }

    /// A shape nested in another uses the outer radius minus the padding
    /// between them, and never less than `extraSmall`.
    enum Radius {
        static let extraSmall: CGFloat = 4
        /// Small icon buttons and hover fills.
        static let small: CGFloat = 6
        /// Rows and inline panels.
        static let medium: CGFloat = 10
        /// Popovers, sheets and floating panels.
        static let large: CGFloat = 14
    }

    enum ControlHeight {
        static let compact: CGFloat = 24
        static let regular: CGFloat = 28
    }

    enum Spacing {
        static let extraExtraSmall: CGFloat = 2
        static let extraSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 24
        static let section: CGFloat = 32
    }

    /// Three weights only: regular, medium and semibold. Text is never smaller
    /// than `caption`.
    enum Typography {
        /// The empty-workspace title.
        static let display = Font.system(size: 20, weight: .semibold)
        /// NOW: the one thing a thread is doing.
        static let now = Font.system(size: 18, weight: .medium)
        /// One of several parallel NOW items.
        static let nowItem = Font.system(size: 15, weight: .medium)
        /// Thread titles.
        static let headline = Font.system(size: 17, weight: .semibold)
        /// Popover and sheet titles.
        static let title = Font.system(size: 15, weight: .semibold)
        /// NOTE text.
        static let note = Font.system(size: 15)
        static let body = Font.system(size: 14)
        static let bodyMedium = Font.system(size: 14, weight: .medium)
        static let callout = Font.system(size: 13)
        /// Section labels (NOW, NOTE, TIMELINE) and small buttons.
        static let label = Font.system(size: 11, weight: .semibold)
        /// Times, counts and secondary lines.
        static let caption = Font.system(size: 11)
        static let captionMedium = Font.system(size: 11, weight: .medium)
        static let icon = Font.system(size: 12, weight: .medium)

        /// Extra space between wrapped lines, so Chinese and English paragraphs
        /// do not sit too tightly.
        static let bodyLineSpacing: CGFloat = 3
        static let nowLineSpacing: CGFloat = 4
        /// Letter spacing for uppercase section labels.
        static let labelTracking: CGFloat = 1.2
    }

    /// A light and a dark value for each token.
    enum Colors {
        static let canvas = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1C1F)
        /// Popovers and floating panels; in dark appearance lighter than the
        /// canvas, because shadows barely show there.
        static let surfaceRaised = Color.dynamic(light: 0xFFFFFF, dark: 0x26262A)
        /// The selected thread column: a quiet neutral fill, like a selected
        /// sidebar row in Zulip Mac.
        static let selectedSurface = Color.dynamic(light: 0xF4F4F6, dark: 0x26262A)
        /// A quiet fill for recessed content.
        static let surfaceSunken = Color.dynamic(light: 0xF5F5F7, dark: 0x151517)
        static let fillHover = Color.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.06)
        static let fillPressed = Color.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.10)
        static let stroke = Color.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
        static let strokeStrong = Color.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.16)
        static let primaryText = Color.dynamic(light: 0x1D1D1F, dark: 0xF2F2F4)
        static let secondaryText = Color.dynamic(light: 0x5E5E66, dark: 0xA3A3AB)
        static let tertiaryText = Color.dynamic(light: 0x6A6A73, dark: 0x8A8A93)
        /// Filled accent: prominent buttons and the window tint.
        static let accent = Color.dynamic(light: 0x4553D0, dark: 0x5F6BE8)
        /// Accent for text and thin marks on the canvas.
        static let accentText = Color.dynamic(light: 0x4553D0, dark: 0x8C95FF)
        static let accentSoft = Color.dynamic(light: 0x4553D0, dark: 0x8C95FF, lightAlpha: 0.12, darkAlpha: 0.18)
        static let success = Color.dynamic(light: 0x1A7F45, dark: 0x5FCB8E)
        /// Milestone stars and storage warnings.
        static let warning = Color.dynamic(light: 0xA5600B, dark: 0xE5A64B)
        static let destructive = Color.dynamic(light: 0xC4313B, dark: 0xFF7A7A)
        /// The underline of a field being edited.
        static let editingUnderline = strokeStrong
        static let disabledOpacity: Double = 0.45
    }

    /// Three durations and one curve. Nothing bounces.
    enum Motion {
        /// Press feedback.
        static var instant: Animation { .easeOut(duration: 0.08) }
        /// Hover, controls that appear on hover, color changes.
        static var fast: Animation { .timingCurve(0.2, 0, 0, 1, duration: 0.12) }
        /// Expanding and collapsing, panels appearing.
        static var base: Animation { .timingCurve(0.2, 0, 0, 1, duration: 0.2) }
    }
}

extension Color {
    /// A color that resolves to `light` in light appearance and `dark` in dark
    /// appearance (sRGB hex values such as `0x4553D0`).
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor.srgb(hex: dark, alpha: darkAlpha)
                : NSColor.srgb(hex: light, alpha: lightAlpha)
        })
    }
}

extension NSColor {
    static func srgb(hex: UInt32, alpha: Double = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

/// A button that lights up under the pointer and darkens while pressed, for
/// small controls without chrome of their own.
struct HoverFillButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = AppTheme.Radius.small

    func makeBody(configuration: Configuration) -> some View {
        HoverFillButton(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverFillButton: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @ViewState private var isHovered = false

        private var fill: Color {
            guard isEnabled else { return .clear }
            if configuration.isPressed { return AppTheme.Colors.fillPressed }
            return isHovered ? AppTheme.Colors.fillHover : .clear
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            configuration.label
                .overlay(shape.fill(fill).allowsHitTesting(false))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : AppTheme.Colors.disabledOpacity)
                .onHover { isHovered = $0 }
                .animation(AppTheme.Motion.fast, value: isHovered)
                .animation(AppTheme.Motion.instant, value: configuration.isPressed)
        }
    }
}

/// A small icon in a square hover target, used for every borderless icon
/// button in the workspace so they share one size, color and feedback.
struct IconButtonLabel: View {
    let systemName: String
    var color: Color = AppTheme.Colors.tertiaryText

    var body: some View {
        Image(systemName: systemName)
            .font(AppTheme.Typography.icon)
            .foregroundStyle(color)
            .frame(width: AppTheme.ControlHeight.compact, height: AppTheme.ControlHeight.compact)
    }
}

/// A small, widely tracked section label (现在 / 备注 / 时间线). The NOW label
/// carries the accent so the eye lands there first.
struct SectionLabel: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text.uppercased())
            .font(AppTheme.Typography.label)
            .tracking(AppTheme.Typography.labelTracking)
            .foregroundStyle(emphasized ? AppTheme.Colors.accentText : AppTheme.Colors.tertiaryText)
    }
}

extension ThreadStatus {
    /// The colour of the status icon under a thread's title.
    var tint: Color {
        switch self {
        case .active: AppTheme.Colors.success
        case .waiting: AppTheme.Colors.warning
        case .sleeping, .done: AppTheme.Colors.tertiaryText
        }
    }
}

/// Short dates in the workspace: "14:05" today, "昨天" yesterday, else "11月3日".
enum ShortDate {
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "昨天" }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let sameYear = calendar.component(.year, from: now) == parts.year
        return (sameYear ? "" : "\(parts.year ?? 0)年") + "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// When a thread was last touched: the time today, otherwise the day.
    static func updated(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now) ? time(date, calendar: calendar) : day(date, now: now, calendar: calendar)
    }
}

extension View {
    /// Animates changes of `value`, or applies them at once when the user has
    /// turned on Reduce Motion.
    func motion<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(ReducibleAnimation(animation: animation, value: value))
    }

    /// The faint underline drawn under a field while it is being edited.
    func editingUnderline(_ isEditing: Bool) -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(isEditing ? AppTheme.Colors.editingUnderline : .clear)
                .frame(height: AppTheme.Metrics.hairline)
                .allowsHitTesting(false)
        }
        .animation(AppTheme.Motion.fast, value: isEditing)
    }
}

private struct ReducibleAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
