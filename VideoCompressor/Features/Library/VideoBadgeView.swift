import SwiftUI

/// Kleines, platzsparendes Badge für die Liste. Wir zeigen es prominent für
/// Spezialformate und in der Detail-Ansicht.
public struct VideoKindBadge: View {
    let kind: VideoKind

    public var body: some View {
        if kind == .standard { EmptyView() }
        else {
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                Text(kind.displayName)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor)
            .accessibilityLabel(Text("Spezialformat: \(kind.displayName)"))
        }
    }

    private var badgeColor: Color {
        switch kind {
        case .spatial: return .purple
        case .cinematic: return .indigo
        case .slowMotion: return .blue
        case .timeLapse: return .orange
        case .screenRecording: return .gray
        case .standard: return .secondary
        }
    }
}

/// HDR-Badge — wird gezeigt, wenn die preflight-Analyse HDR/Dolby-Vision
/// erkennt.
public struct HDRBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
            Text("HDR")
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.yellow.opacity(0.22), in: Capsule())
        .foregroundStyle(Color.orange)
        .accessibilityLabel(Text("HDR-Inhalt"))
    }
}
