import SwiftUI

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var state = UIState(phase: .idle, detail: "Hold Command to speak", expanded: false)
    var onConfirm: () -> Void = {}
    var onCancel: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onQuit: () -> Void = {}
}

struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 806.0
        let sy = rect.height / 210.0
        // Preserve every supplied control point while translating the reference's
        // 10-unit canvas margin away so the silhouette itself meets the screen.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: (y - 10) * sy) }
        var path = Path()
        path.move(to: p(18, 10))
        path.addLine(to: p(756, 10))
        path.addCurve(to: p(706, 60), control1: p(728.39, 10), control2: p(706, 32.39))
        path.addLine(to: p(706, 88))
        path.addCurve(to: p(656, 138), control1: p(706, 115.61), control2: p(683.61, 138))
        path.addLine(to: p(118, 138))
        path.addCurve(to: p(68, 88), control1: p(90.39, 138), control2: p(68, 115.61))
        path.addLine(to: p(68, 60))
        path.addCurve(to: p(18, 10), control1: p(68, 32.39), control2: p(45.61, 10))
        path.closeSubpath()
        return path
    }
}

private struct NotchOpenEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 806.0
        let sy = rect.height / 210.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: (y - 10) * sy) }
        var path = Path()
        path.move(to: p(756, 10))
        path.addCurve(to: p(706, 60), control1: p(728.39, 10), control2: p(706, 32.39))
        path.addLine(to: p(706, 88))
        path.addCurve(to: p(656, 138), control1: p(706, 115.61), control2: p(683.61, 138))
        path.addLine(to: p(118, 138))
        path.addCurve(to: p(68, 88), control1: p(90.39, 138), control2: p(68, 115.61))
        path.addLine(to: p(68, 60))
        path.addCurve(to: p(18, 10), control1: p(68, 32.39), control2: p(45.61, 10))
        return path
    }
}

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @State private var hovering = false

    private var state: UIState { model.state }
    private var isOpen: Bool { state.expanded || state.phase != .idle }
    private var size: CGSize {
        let result = state.phase == .success || state.phase == .error
        return CGSize(width: isOpen ? (state.needsConfirmation ? 520 : 430) : 190,
                      height: isOpen ? (state.needsConfirmation ? 350 : (result && state.requestMetrics != nil ? 185 : 120)) : 63)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            ZStack {
                NotchShape().fill(.ultraThinMaterial)
                NotchShape().fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.00),
                            .init(color: .black, location: 0.55),
                            .init(color: Color(red: 0.03, green: 0.07, blue: 0.10), location: 0.72),
                            .init(color: Color(red: 0.24, green: 0.42, blue: 0.54), location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                if isOpen {
                    BottomGlassGlow(level: state.level, phase: state.phase).clipShape(NotchShape())
                    NotchBeam(phase: state.phase).clipShape(NotchShape())
                }
                if isOpen { content.transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top))) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape())
            .overlay {
                if isOpen { NotchOpenEdge().stroke(.white.opacity(0.09), lineWidth: 0.65) }
            }
            .shadow(color: .black.opacity(0.62), radius: 24, y: 11)
            .shadow(color: glowColor.opacity(isOpen ? 0.20 : 0), radius: 20, y: 9)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: size)
            .onHover { hovering = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ThinkingOrb(state: orbState, size: .px64, theme: .dark, speed: orbSpeed, displaySize: 15)
                    .frame(width: 16, height: 16)
                Spacer(minLength: 0)
                if hovering {
                    Button(action: model.onDismiss) { Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(NotchIconButtonStyle())
                        .help("Collapse")
                    Button(action: model.onQuit) { Image(systemName: "power").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(NotchIconButtonStyle(tint: .red))
                        .help("Quit Jev Notch")
                }
            }
            .frame(height: 17)

            Text(displayText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(state.needsConfirmation ? 5 : 2)
                .frame(maxWidth: .infinity, minHeight: 21, alignment: .leading)
                .shadow(color: .black.opacity(0.65), radius: 5, y: 2)

            if let metrics = state.requestMetrics,
               state.phase == .success || state.phase == .error || state.phase == .confirm {
                Text(metrics.compactLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.47))
                    .lineLimit(1)
                    .help("Elapsed processing time, excluding time waiting for confirmation. Estimated Jev API cost uses reported input tokens; local Ollama and device costs are not included.")
            }

            if state.needsConfirmation {
                HStack(spacing: 9) {
                    Spacer(minLength: 8)
                    Button("Cancel", action: model.onCancel).buttonStyle(NotchActionButtonStyle())
                    Button("Run", action: model.onConfirm).buttonStyle(NotchActionButtonStyle(prominent: true))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Keep the orb centered in the physical notch band and leave breathing room
        // between the command line and the lower curve.
        .padding(.horizontal, 74)
        .padding(.top, 13)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.16), value: hovering)
    }

    private var displayText: String {
        if state.phase == .success || state.phase == .error || state.phase == .confirm {
            return state.detail.isEmpty ? state.transcript : state.detail
        }
        if !state.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return state.transcript }
        return state.detail
    }

    private var glowColor: Color {
        switch state.phase { case .success: .green; case .error: .red; case .confirm: .orange; default: .cyan }
    }

    private var orbState: OrbState {
        switch state.phase {
        case .idle: .breathing
        case .listening: .listening
        case .routing: .searching
        case .executing: .working
        case .success: .composing
        case .error: .shaping
        case .confirm: .connecting
        }
    }
    private var orbSpeed: Double { state.phase == .routing ? 1.25 : 0.9 }
}

private struct NotchBeam: View {
    let phase: NotchPhase
    var body: some View {
        let colors: [Color] = phase == .error
            ? [.red.opacity(0.46), .orange.opacity(0.66), .red.opacity(0.46)]
            : [.blue.opacity(0.34), .cyan.opacity(0.74), .blue.opacity(0.34)]
        NotchOpenEdge()
            .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), lineWidth: 0.85)
            .shadow(color: (phase == .error ? Color.red : Color.cyan).opacity(0.22), radius: 5)
            .opacity(0.78)
        .allowsHitTesting(false)
    }
}

private struct BottomGlassGlow: View {
    let level: Double
    let phase: NotchPhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let processing = phase == .routing || phase == .executing
            let movement = processing ? sin(t * 1.8) * 48 : 0
            let color: Color = phase == .error ? .red : (phase == .confirm ? .orange : .cyan)
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.clear, color.opacity(0.06), color.opacity(0.28 + level * 0.20)], startPoint: .top, endPoint: .bottom)
                Ellipse()
                    .fill(RadialGradient(colors: [color.opacity(0.42 + level * 0.25), .blue.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 150))
                    .frame(width: 300 + level * 90, height: 44 + level * 35)
                    .blur(radius: 13)
                    .offset(x: movement, y: 22)
            }
            .animation(.easeOut(duration: 0.10), value: level)
        }
        .allowsHitTesting(false)
    }
}

private struct NotchIconButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint.opacity(configuration.isPressed ? 0.96 : 0.52))
            .frame(width: 22, height: 21)
            .background(.white.opacity(configuration.isPressed ? 0.10 : 0.045), in: Circle())
            .contentShape(Circle())
    }
}

private struct NotchActionButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 72, height: 25)
            .background(
                prominent
                    ? AnyShapeStyle(LinearGradient(colors: [.cyan.opacity(0.46), .blue.opacity(0.38)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(.white.opacity(0.065)),
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white.opacity(prominent ? 0.18 : 0.08), lineWidth: 0.6))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
