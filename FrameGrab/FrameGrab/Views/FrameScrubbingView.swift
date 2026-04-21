import SwiftUI
import AVKit

struct FrameScrubbingView: View {
    @ObservedObject var viewModel: VideoViewModel
    @State private var isScrubbing = false
    @State private var showCaptureFlash = false

    var body: some View {
        VStack(spacing: 0) {
            // Video Player
            VideoPlayerLayer(player: viewModel.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay(alignment: .topTrailing) {
                    if showCaptureFlash {
                        Color.white
                            .opacity(0.8)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .center) {
                    if viewModel.isCapturing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.5)
                            .padding(20)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

            // Timeline & Controls
            VStack(spacing: 16) {
                // Timestamp display
                HStack {
                    Text(formatTime(viewModel.currentTime))
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formatTime(viewModel.duration))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                // Thumbnail strip + scrubber
                ThumbnailScrubber(
                    viewModel: viewModel,
                    isScrubbing: $isScrubbing
                )

                // Playback controls
                HStack(spacing: 32) {
                    // Step back
                    Button {
                        viewModel.stepFrame(forward: false)
                    } label: {
                        Image(systemName: "backward.frame.fill")
                            .font(.title2)
                    }

                    // Play/Pause
                    Button {
                        viewModel.togglePlayback()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }

                    // Step forward
                    Button {
                        viewModel.stepFrame(forward: true)
                    } label: {
                        Image(systemName: "forward.frame.fill")
                            .font(.title2)
                    }
                }
                .foregroundStyle(.primary)

                // Capture button
                Button {
                    captureFrame()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                        Text("Capture Frame")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.isCapturing)
            }
            .padding(16)
            .background(.regularMaterial)
        }
        .onChange(of: viewModel.captureError) { _, error in
            // Error handled by parent if needed
        }
    }

    private func captureFrame() {
        if viewModel.isPlaying { viewModel.togglePlayback() }

        withAnimation(.easeIn(duration: 0.05)) {
            showCaptureFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.15)) {
                showCaptureFlash = false
            }
        }

        viewModel.captureCurrentFrame()
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let minutes = total / 60
        let secs = total % 60
        let millis = Int((seconds - Double(total)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, millis)
    }
}

// MARK: - Thumbnail Scrubber

struct ThumbnailScrubber: View {
    @ObservedObject var viewModel: VideoViewModel
    @Binding var isScrubbing: Bool

    private let height: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Thumbnail strip background
                ThumbnailStrip(viewModel: viewModel)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Playhead
                let progress = viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0
                let x = CGFloat(progress) * geo.size.width

                // Tinted overlay showing elapsed portion
                Color.black.opacity(0.35)
                    .frame(width: geo.size.width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Color.accentColor.opacity(0.2)
                    .frame(width: max(0, x), height: height)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                    )

                // Playhead line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: height + 8)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: x - 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        if viewModel.isPlaying { viewModel.togglePlayback() }
                        let progress = (value.location.x / geo.size.width).clamped(to: 0...1)
                        viewModel.seek(to: progress * viewModel.duration)
                    }
                    .onEnded { _ in
                        isScrubbing = false
                    }
            )
        }
        .frame(height: height + 8)
    }
}

// MARK: - Thumbnail Strip

struct ThumbnailStrip: View {
    @ObservedObject var viewModel: VideoViewModel

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                let sortedTimes = viewModel.thumbnailCache.keys.sorted()
                if sortedTimes.isEmpty {
                    Color.gray.opacity(0.3)
                } else {
                    ForEach(sortedTimes, id: \.self) { t in
                        if let img = viewModel.thumbnailCache[t] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: geo.size.width / CGFloat(sortedTimes.count),
                                    height: geo.size.height
                                )
                                .clipped()
                        } else {
                            Color.gray.opacity(0.3)
                                .frame(width: geo.size.width / CGFloat(sortedTimes.count))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AVPlayer UIViewRepresentable

struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

class PlayerUIView: UIView {
    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
