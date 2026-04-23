import SwiftUI
import UIKit

/// Eine Zeile in der Library-Liste. Zeigt Thumbnail, Metadaten und ein
/// Auswahl-Indikator. Thumbnail wird lazy beim ersten Erscheinen geladen.
public struct VideoRowView: View {
    let item: LibraryVideoItem
    let isSelected: Bool
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    let thumbnailLoader: (String) async -> UIImage?

    @State private var thumbnail: UIImage?

    public var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.gray.opacity(0.15)
                                .overlay(ProgressView().scaleEffect(0.7))
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipped()
                    .cornerRadius(8)

                    Text(Formatting.duration(item.duration))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(Formatting.bytes(item.fileSize))
                            .font(.headline)
                        if item.kind != .standard {
                            VideoKindBadge(kind: item.kind)
                        }
                    }
                    Text(item.resolutionString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Formatting.date(item.creationDate))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)

                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityLabel(isSelected ? "Auswahl entfernen" : "Auswählen")
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: item.id) {
            if thumbnail == nil {
                thumbnail = await thumbnailLoader(item.id)
            }
        }
    }
}
