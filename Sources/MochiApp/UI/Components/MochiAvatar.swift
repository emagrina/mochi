import SwiftUI
import MochiCore

/// The character at the center of Mochi's identity: a soft rounded body with a tiny face
/// whose expression encodes `AgentStatus`. Fully vector/programmatic (no bitmap assets) so
/// it stays crisp from menu-bar size up to the detail view, and provider accessories are
/// simple colored shapes rather than any third-party logo (product spec section 4).
public struct MochiAvatar: View {
    public let status: AgentStatus
    public let provider: AgentProvider
    public let size: CGFloat
    public let reducedMotion: Bool

    @State private var breathe = false
    @State private var bounce = false
    @State private var shakeTrigger = 0

    public init(status: AgentStatus, provider: AgentProvider, size: CGFloat = 32, reducedMotion: Bool = false) {
        self.status = status
        self.provider = provider
        self.size = size
        self.reducedMotion = reducedMotion
    }

    public var body: some View {
        ZStack {
            body(for: status)
            MochiFace(status: status, size: size)
            accessory
        }
        .frame(width: size, height: size)
        .scaleEffect(breatheScale * (bounce ? 1.12 : 1))
        .phaseAnimator([0, 1, 2, 3, 0], trigger: shakeTrigger) { content, phase in
            content.offset(x: reducedMotion ? 0 : shakeOffset(for: phase))
        } animation: { _ in .linear(duration: 0.06) }
        .accessibilityHidden(true) // the row/detail view supplies a full text label instead.
        .onAppear { startAmbientAnimation() }
        .onChange(of: status) { _, newValue in
            guard !reducedMotion else { return }
            if newValue == .done {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { bounce = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bounce = false }
                }
            }
            if newValue == .error {
                shakeTrigger += 1
            }
            startAmbientAnimation()
        }
    }

    private func shakeOffset(for phase: Int) -> CGFloat {
        switch phase {
        case 1: return -size * 0.06
        case 2: return size * 0.06
        case 3: return -size * 0.03
        default: return 0
        }
    }

    @ViewBuilder
    private func body(for status: AgentStatus) -> some View {
        RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [MochiColors.body, MochiColors.body.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                    .strokeBorder(statusTint.opacity(statusTint == .clear ? 0 : 0.55), lineWidth: max(1, size * 0.035))
            )
            .overlay(
                // A faint top-left highlight sells the "soft rice cake" look without full
                // glassmorphism — one subtle ellipse, not a gradient wash over everything.
                Ellipse()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: size * 0.4, height: size * 0.22)
                    .offset(x: -size * 0.14, y: -size * 0.26)
                    .blendMode(.plusLighter)
            )
            .shadow(color: MochiColors.bodyShadow, radius: size * 0.06, y: size * 0.03)
            .opacity(status == .offline ? 0.45 : 1)
    }

    private var statusTint: Color {
        switch status {
        case .needsPermission: return MochiColors.attention
        case .error: return MochiColors.errorTint
        case .done: return MochiColors.successTint
        default: return .clear
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch provider {
        case .claude:
            Circle()
                .fill(MochiColors.claudeAccent)
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(x: size * 0.3, y: -size * 0.34)
        case .codex:
            RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                .fill(MochiColors.codexAccent)
                .frame(width: size * 0.17, height: size * 0.17)
                .offset(x: size * 0.3, y: -size * 0.34)
        case .openclaw:
            Circle()
                .fill(MochiColors.openClawAccent)
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(x: size * 0.3, y: -size * 0.34)
        case .generic:
            EmptyView()
        }
    }

    private var breatheScale: CGFloat {
        guard !reducedMotion else { return 1 }
        guard status.isActive || status == .idle else { return 1 }
        return breathe ? 1.04 : 1.0
    }

    private func startAmbientAnimation() {
        guard !reducedMotion else { breathe = false; return }
        guard status.isActive || status == .idle else { breathe = false; return }
        withAnimation(.easeInOut(duration: status == .idle ? 2.6 : 1.6).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }
}

/// Eyes + mouth, drawn as plain shapes sized relative to the body so the face reads clearly
/// even at 16x16 menu bar scale. Each `AgentStatus` gets a genuinely different shape, not
/// just a different color, per the accessibility note in the product spec (don't rely on
/// color alone).
private struct MochiFace: View {
    let status: AgentStatus
    let size: CGFloat

    var body: some View {
        VStack(spacing: size * 0.06) {
            eyes
            mouth
        }
        .offset(y: size * 0.04)
    }

    private var eyeSize: CGFloat { size * 0.12 }
    private var eyeGap: CGFloat { size * 0.16 }

    @ViewBuilder
    private var eyes: some View {
        switch status {
        case .idle, .offline, .paused:
            HStack(spacing: eyeGap) {
                closedEye
                closedEye
            }
        case .needsPermission:
            HStack(spacing: eyeGap) {
                wideEye
                wideEye
            }
        case .error:
            HStack(spacing: eyeGap) {
                crossEye
                crossEye
            }
        case .testing:
            glasses
        case .thinking:
            HStack(spacing: eyeGap) {
                dotEye
                squintEye
            }
        case .waiting:
            HStack(spacing: eyeGap) {
                sideEye
                sideEye
            }
        case .done:
            HStack(spacing: eyeGap) {
                happyEye
                happyEye
            }
        case .working, .starting, .custom:
            HStack(spacing: eyeGap) {
                dotEye
                dotEye
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch status {
        case .done:
            Capsule().fill(MochiColors.face).frame(width: size * 0.22, height: size * 0.05)
                .mask(SmileMask())
        case .error:
            WavyLine().stroke(MochiColors.face, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.2, height: size * 0.05)
        case .needsPermission:
            Ellipse().fill(MochiColors.face).frame(width: size * 0.09, height: size * 0.07)
        case .idle, .offline, .paused:
            Capsule().fill(MochiColors.face).frame(width: size * 0.16, height: size * 0.025)
        default:
            Capsule().fill(MochiColors.face).frame(width: size * 0.1, height: size * 0.035)
        }
    }

    private var dotEye: some View {
        Circle().fill(MochiColors.face).frame(width: eyeSize, height: eyeSize)
    }

    private var closedEye: some View {
        Capsule().fill(MochiColors.face).frame(width: eyeSize * 1.3, height: eyeSize * 0.3)
    }

    private var wideEye: some View {
        Circle().fill(MochiColors.face).frame(width: eyeSize * 1.3, height: eyeSize * 1.3)
    }

    private var crossEye: some View {
        ZStack {
            Rectangle().fill(MochiColors.face).frame(width: eyeSize * 1.2, height: eyeSize * 0.22).rotationEffect(.degrees(45))
            Rectangle().fill(MochiColors.face).frame(width: eyeSize * 1.2, height: eyeSize * 0.22).rotationEffect(.degrees(-45))
        }
        .frame(width: eyeSize * 1.2, height: eyeSize * 1.2)
    }

    private var squintEye: some View {
        Capsule().fill(MochiColors.face).frame(width: eyeSize * 1.1, height: eyeSize * 0.25)
    }

    private var sideEye: some View {
        Circle().fill(MochiColors.face).frame(width: eyeSize, height: eyeSize)
            .offset(x: eyeSize * 0.25)
    }

    private var happyEye: some View {
        HappyEyeShape()
            .stroke(MochiColors.face, style: StrokeStyle(lineWidth: eyeSize * 0.35, lineCap: .round))
            .frame(width: eyeSize * 1.1, height: eyeSize * 0.8)
    }

    private var glasses: some View {
        HStack(spacing: eyeSize * 0.3) {
            RoundedRectangle(cornerRadius: eyeSize * 0.2).stroke(MochiColors.face, lineWidth: eyeSize * 0.18)
                .frame(width: eyeSize * 1.2, height: eyeSize * 1.0)
            RoundedRectangle(cornerRadius: eyeSize * 0.2).stroke(MochiColors.face, lineWidth: eyeSize * 0.18)
                .frame(width: eyeSize * 1.2, height: eyeSize * 1.0)
        }
    }
}

/// An upward-curving arc, used both for the happy-eye crescents and (clipped to a capsule)
/// the smiling mouth.
private struct HappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height), control: CGPoint(x: rect.width / 2, y: -rect.height * 0.6))
        return path
    }
}

private struct SmileMask: View {
    var body: some View {
        HappyEyeShape()
            .stroke(Color.black, style: StrokeStyle(lineWidth: 100, lineCap: .round))
    }
}

private struct WavyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height / 2))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height / 2),
            control1: CGPoint(x: rect.width * 0.25, y: 0),
            control2: CGPoint(x: rect.width * 0.75, y: rect.height)
        )
        return path
    }
}
