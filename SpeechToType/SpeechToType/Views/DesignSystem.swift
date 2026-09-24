//
//  DesignSystem.swift
//  SpeechToType
//
//  The app's shared look: the animated mesh-gradient background, Liquid Glass cards,
//  page headers, icon badges, key caps and a few layout helpers used by all views.
//

import SwiftUI

// MARK: - Background

/// Slowly drifting mesh gradient behind the glass UI. It pauses while the window is in
/// the background and stands still with Reduce Motion.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !appearsActive)) { context in
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: context.date.timeIntervalSinceReferenceDate),
                colors: colorScheme == .dark ? Self.darkColors : Self.lightColors
            )
        }
        .ignoresSafeArea()
    }

    /// Corners stay put, the edge points glide along their edge and the center wanders.
    /// Periods of about a minute keep the motion calm.
    private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func drift(_ speed: Double, _ phase: Double, _ amplitude: Float) -> Float {
            Float(sin(time * speed + phase)) * amplitude
        }
        return [
            [0, 0], [0.5 + drift(0.11, 0.0, 0.18), 0], [1, 0],
            [0, 0.5 + drift(0.09, 1.3, 0.2)],
            [0.5 + drift(0.07, 2.1, 0.16), 0.5 + drift(0.1, 0.7, 0.16)],
            [1, 0.5 + drift(0.12, 2.8, 0.2)],
            [0, 1], [0.5 + drift(0.08, 4.0, 0.18), 1], [1, 1]
        ]
    }

    private static let darkColors: [Color] = [
        Color(red: 0.06, green: 0.08, blue: 0.20), Color(red: 0.15, green: 0.11, blue: 0.36), Color(red: 0.26, green: 0.11, blue: 0.40),
        Color(red: 0.05, green: 0.19, blue: 0.36), Color(red: 0.17, green: 0.19, blue: 0.50), Color(red: 0.32, green: 0.13, blue: 0.38),
        Color(red: 0.04, green: 0.24, blue: 0.30), Color(red: 0.07, green: 0.13, blue: 0.33), Color(red: 0.17, green: 0.08, blue: 0.25)
    ]

    private static let lightColors: [Color] = [
        Color(red: 0.84, green: 0.89, blue: 1.00), Color(red: 0.89, green: 0.86, blue: 1.00), Color(red: 0.97, green: 0.87, blue: 0.96),
        Color(red: 0.82, green: 0.92, blue: 1.00), Color(red: 0.88, green: 0.88, blue: 1.00), Color(red: 0.95, green: 0.88, blue: 0.98),
        Color(red: 0.82, green: 0.96, blue: 0.93), Color(red: 0.86, green: 0.92, blue: 1.00), Color(red: 1.00, green: 0.92, blue: 0.87)
    ]
}

// MARK: - Glass

extension View {
    /// Content on a Liquid Glass card
    func glassCard(padding: CGFloat = 18, cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
    }

    /// Subtle filled field for controls that sit on a glass surface (no glass on glass)
    func insetField(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

// MARK: - Page structure

/// Large title with an optional subtitle and trailing controls, at the top of every page.
struct PageHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Small heading above a group of cards
struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

/// Centered placeholder for empty lists and unselected detail areas
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title3.weight(.semibold))
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small components

/// Colored rounded square with a white symbol, like the icons in System Settings
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// A keyboard key, e.g. for shortcut hints
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14))
            )
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
    }
}

/// Capsule with an icon and a short value (model, duration, word count …)
struct InfoChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

/// Search field for glass panels
struct PanelSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "search"), text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .insetField(cornerRadius: 10)
    }
}

/// Big number with an icon and a caption, on glass
struct StatTile: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14, cornerRadius: 20)
    }
}

/// Glowing orb that shows the dictation state; it breathes while idle and pulses with
/// the input level while recording.
struct DictationOrb: View {
    enum Phase {
        case idle
        case recording
        case processing
        case inactive
    }

    let phase: Phase
    var level: Float = 0
    var size: CGFloat = 76

    @State private var breathing = false

    private var colors: [Color] {
        switch phase {
        case .idle: return [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.38, blue: 1.0)]
        case .recording: return [Color(red: 1.0, green: 0.36, blue: 0.36), Color(red: 1.0, green: 0.58, blue: 0.24)]
        case .processing: return [Color(red: 0.25, green: 0.75, blue: 0.95), Color(red: 0.45, green: 0.45, blue: 1.0)]
        case .inactive: return [Color.gray.opacity(0.7), Color.gray.opacity(0.45)]
        }
    }

    private var symbol: String {
        switch phase {
        case .idle, .inactive: return "mic.fill"
        case .recording: return "waveform"
        case .processing: return "ellipsis"
        }
    }

    var body: some View {
        let levelScale = phase == .recording ? 1 + CGFloat(min(max(level, 0), 1)) * 0.22 : 1
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [colors[0].opacity(0.55), .clear], center: .center, startRadius: size * 0.2, endRadius: size * 0.95))
                .frame(width: size * 1.9, height: size * 1.9)
                .scaleEffect(breathing ? 1.06 : 0.94)
                .scaleEffect(levelScale)
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: colors[0].opacity(0.5), radius: 14, y: 4)
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: phase == .processing)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size * 1.9, height: size * 1.9)
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(.easeInOut(duration: 0.35), value: phase)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

// MARK: - Layout

/// Lays out its children in rows and wraps them to the next row when a row is full
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
