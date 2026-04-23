import SwiftUI

public struct ExportReviewItem: Identifiable, Hashable {
    public let id: String
    public let item: LibraryVideoItem
    public let result: ExportResult

    public init(item: LibraryVideoItem, result: ExportResult) {
        self.id = item.id
        self.item = item
        self.result = result
    }
}

public struct ExportReviewScreen: View {
    private let items: [ExportReviewItem]
    private let onDone: () -> Void
    @State private var selection: String

    public init(items: [ExportReviewItem], onDone: @escaping () -> Void) {
        self.items = items
        self.onDone = onDone
        _selection = State(initialValue: items.first?.id ?? "")
    }

    public var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Keine Ergebnisse", systemImage: "film")
            } else {
                VStack(spacing: 8) {
                    TabView(selection: $selection) {
                        ForEach(items) { item in
                            ExportReviewPage(
                                reviewItem: item,
                                isActive: selection == item.id
                            )
                            .tag(item.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .automatic))

                    if items.count > 1 {
                        Text("\(currentIndex + 1) von \(items.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Ergebnis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Schliessen", action: onDone)
            }
        }
    }

    private var currentIndex: Int {
        items.firstIndex { $0.id == selection } ?? 0
    }
}

private struct ExportReviewPage: View {
    let reviewItem: ExportReviewItem
    let isActive: Bool
    @State private var viewModel: VideoDetailViewModel

    init(reviewItem: ExportReviewItem, isActive: Bool) {
        self.reviewItem = reviewItem
        self.isActive = isActive
        _viewModel = State(initialValue: VideoDetailViewModel(
            item: reviewItem.item,
            environment: AppEnvironment.shared,
            initialResult: reviewItem.result
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VideoComparisonPlayerView(viewModel: viewModel)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                ResultCard(result: viewModel.lastResult ?? reviewItem.result)

                HStack {
                    Text(reviewItem.item.resolutionString)
                    Spacer()
                    Text(Formatting.duration(reviewItem.item.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .task {
            await viewModel.loadThumbnail()
            await viewModel.loadOriginalPlayback()
            await viewModel.loadCompressedPlaybackIfAvailable()
            if isActive {
                await viewModel.playPlayback(preferred: .compressed)
            }
        }
        .onChange(of: isActive) { _, active in
            Task {
                if active {
                    await viewModel.playPlayback(preferred: .compressed)
                } else {
                    viewModel.pausePlayback()
                }
            }
        }
        .onDisappear {
            viewModel.pausePlayback()
        }
    }
}
