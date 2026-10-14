#if canImport(SwiftUI)
import SwiftUI

/// The "Sign in with Nemi" button: a capsule with the Nemi wordmark.
///
/// ```swift
/// SignInWithNemiButton {
///     Task { try? await model.signIn() }
/// }
/// ```
public struct SignInWithNemiButton: View {
    /// The button's colors.
    public enum Style: Sendable {
        /// Black capsule, white text. The default; works on light and dark backgrounds.
        case black
        /// White capsule, black text, for dark backgrounds.
        case white
        /// Black in light mode, white in dark mode.
        case automatic
    }

    /// The leading words.
    public enum Label: Sendable {
        case signIn
        case continueWith
        case signUp

        var prefix: String {
            switch self {
            case .signIn: return "Sign in with"
            case .continueWith: return "Continue with"
            case .signUp: return "Sign up with"
            }
        }
    }

    private let label: Label
    private let style: Style
    private let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    public init(_ label: Label = .signIn, style: Style = .black, action: @escaping () -> Void) {
        self.label = label
        self.style = style
        self.action = action
    }

    private var isBlack: Bool {
        switch style {
        case .black: return true
        case .white: return false
        case .automatic: return colorScheme != .dark
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                NemiMark()
                    .frame(width: 18, height: 18)
                (Text(label.prefix + " ") + Text("Nemi").fontWeight(.bold))
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(isBlack ? .white : .black)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(isBlack ? Color.black : Color.white))
            .overlay(Capsule().strokeBorder(isBlack ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label.prefix + " Nemi"))
        .accessibilityAddTraits(.isButton)
    }
}

/// A simple "N" monogram in a ring, drawn in the current foreground color.
struct NemiMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().stroke(lineWidth: size * 0.1)
                Path { path in
                    let inset = size * 0.3
                    path.move(to: CGPoint(x: inset, y: size - inset))
                    path.addLine(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: size - inset, y: size - inset))
                    path.addLine(to: CGPoint(x: size - inset, y: inset))
                }
                .stroke(style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
struct SignInWithNemiButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SignInWithNemiButton {}
            SignInWithNemiButton(.continueWith, style: .white) {}
            SignInWithNemiButton(.signUp, style: .automatic) {}
        }
        .padding()
        .background(Color.gray.opacity(0.3))
    }
}
#endif
#endif
