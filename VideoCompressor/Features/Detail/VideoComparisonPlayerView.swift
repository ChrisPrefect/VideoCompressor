import AVKit
import SwiftUI

struct VideoComparisonPlayerView: View {
    @Bindable var viewModel: VideoDetailViewModel

    var body: some View {
        ZStack {
            Color.black

            if viewModel.originalPlaybackReady {
                VideoPlayer(player: viewModel.originalPlayer)
                    .opacity(opacity(for: .original))
                    .allowsHitTesting(!viewModel.comparisonAvailable && viewModel.currentPlaybackSource == .original)
            }

            if viewModel.compressedPlaybackReady {
                VideoPlayer(player: viewModel.compressedPlayer)
                    .opacity(opacity(for: .compressed))
                    .allowsHitTesting(!viewModel.comparisonAvailable && viewModel.currentPlaybackSource == .compressed)
            }

            if !viewModel.playerIsReady {
                placeholder
            }
        }
        .aspectRatio(viewModel.item.aspectRatio, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            if viewModel.compressedIsAvailable {
                Text(viewModel.currentPlaybackSource.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
            }
        }
        .overlay {
            if viewModel.comparisonAvailable {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.togglePlaybackSource() }
                    }
            }
        }
    }

    private var placeholder: some View {
        Group {
            if let thumb = viewModel.thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView())
            }
        }
    }

    private func opacity(for source: VideoDetailViewModel.PlaybackSource) -> Double {
        viewModel.currentPlaybackSource == source ? 1 : 0
    }
}
