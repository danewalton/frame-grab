import SwiftUI
import AVFoundation
import PhotosUI
import Photos

@MainActor
class VideoViewModel: ObservableObject {
    @Published var videoURL: URL?
    @Published var player: AVPlayer?
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var capturedFrames: [CapturedFrame] = []
    @Published var isCapturing = false
    @Published var captureError: String?
    @Published var thumbnailCache: [Double: UIImage] = [:]
    @Published var neighborFrames: [(time: Double, image: UIImage)] = []

    private var asset: AVAsset?
    private var timeObserver: Any?
    private var playerForDeinit: AVPlayer?   // nonisolated-safe reference for deinit
    private let frameExtractor = FrameExtractor()
    private var frameRate: Double = 30.0
    private var neighborTask: Task<Void, Never>?

    // MARK: - Video Loading

    func loadVideo(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else { return }
            await setupPlayer(url: movie.url)
        } catch {
            captureError = "Failed to load video: \(error.localizedDescription)"
        }
    }

    func loadVideo(from url: URL) async {
        await setupPlayer(url: url)
    }

    private func setupPlayer(url: URL) async {
        // Clean up previous
        removeTimeObserver()
        player?.pause()

        let asset = AVURLAsset(url: url)
        self.asset = asset

        do {
            let durationValue = try await asset.load(.duration)
            self.duration = CMTimeGetSeconds(durationValue)
        } catch {
            captureError = "Could not read video duration"
            return
        }

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        self.videoURL = url
        self.currentTime = 0
        self.isPlaying = false
        self.capturedFrames = []

        addTimeObserver(to: player)
        playerForDeinit = player
        await loadFrameRate()
        await generateThumbnailStrip()
        await generateNeighborFrames(around: 0)
    }

    // MARK: - Playback Control

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= duration - 0.05 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to time: Double) {
        guard let player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        scheduleNeighborFrameUpdate()
    }

    func stepFrame(forward: Bool) {
        let frameStep = 1.0 / frameRate
        let newTime = max(0, min(duration, currentTime + (forward ? frameStep : -frameStep)))
        seek(to: newTime)
    }

    // MARK: - Frame Capture

    func captureCurrentFrame() {
        guard let asset else { return }

        isCapturing = true
        captureError = nil

        Task {
            do {
                let image = try await frameExtractor.extractFrame(
                    from: asset,
                    at: CMTime(seconds: currentTime, preferredTimescale: 600)
                )
                let frame = CapturedFrame(image: image, timestamp: currentTime)
                capturedFrames.insert(frame, at: 0)
            } catch {
                captureError = "Failed to capture frame: \(error.localizedDescription)"
            }
            isCapturing = false
        }
    }

    // MARK: - Thumbnail Strip

    private func loadFrameRate() async {
        guard let asset else { return }
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let fps = try await track.load(.nominalFrameRate)
                frameRate = max(1, Double(fps))
            }
        } catch {}
    }

    private func scheduleNeighborFrameUpdate() {
        neighborTask?.cancel()
        neighborTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            await self.generateNeighborFrames(around: self.currentTime)
        }
    }

    private func generateNeighborFrames(around time: Double) async {
        guard let asset, duration > 0 else { return }
        let frameStep = 1.0 / frameRate
        let offsets = [-2, -1, 0, 1, 2]

        await withTaskGroup(of: (Double, UIImage?).self) { group in
            for offset in offsets {
                let t = max(0, min(duration, time + Double(offset) * frameStep))
                group.addTask { [weak self] in
                    guard let self else { return (t, nil) }
                    let img = try? await self.frameExtractor.extractFrame(
                        from: asset,
                        at: CMTime(seconds: t, preferredTimescale: 600),
                        maximumSize: CGSize(width: 120, height: 80)
                    )
                    return (t, img)
                }
            }
            var raw: [(Double, UIImage?)] = []
            for await result in group { raw.append(result) }
            neighborFrames = raw
                .compactMap { t, img in img.map { (time: t, image: $0) } }
                .sorted { $0.time < $1.time }
        }
    }

    private func generateThumbnailStrip() async {
        guard let asset else { return }
        thumbnailCache.removeAll()

        let count = 7
        guard duration > 0 else { return }

        await withTaskGroup(of: (Double, UIImage?).self) { group in
            for i in 0..<count {
                let t = duration * Double(i) / Double(count - 1)
                group.addTask { [weak self] in
                    guard let self else { return (t, nil) }
                    let img = try? await self.frameExtractor.extractFrame(
                        from: asset,
                        at: CMTime(seconds: t, preferredTimescale: 600),
                        maximumSize: CGSize(width: 120, height: 80)
                    )
                    return (t, img)
                }
            }
            for await (t, image) in group {
                if let image { thumbnailCache[t] = image }
            }
        }
    }

    // MARK: - Time Observer

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            if let item = player.currentItem {
                let itemDuration = CMTimeGetSeconds(item.duration)
                if itemDuration.isFinite && self.currentTime >= itemDuration - 0.05 {
                    self.isPlaying = false
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    nonisolated deinit {
        if let observer = timeObserver {
            playerForDeinit?.removeTimeObserver(observer)
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}
