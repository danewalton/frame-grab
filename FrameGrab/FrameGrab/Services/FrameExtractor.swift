import AVFoundation
import UIKit

actor FrameExtractor {

    func extractFrame(
        from asset: AVAsset,
        at time: CMTime,
        maximumSize: CGSize = .zero
    ) async throws -> UIImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        if maximumSize != .zero {
            generator.maximumSize = maximumSize
        }

        let (cgImage, _) = try await generator.image(at: time)
        return UIImage(cgImage: cgImage)
    }

    func extractFrames(
        from asset: AVAsset,
        at times: [CMTime],
        maximumSize: CGSize = .zero,
        progressHandler: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        if maximumSize != .zero {
            generator.maximumSize = maximumSize
        }

        let nsValues = times.map { NSValue(time: $0) }
        var images: [CMTimeValue: UIImage] = [:]
        var errors: [Error] = []
        var completed = 0

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: nsValues) { _, cgImage, _, result, error in
                completed += 1
                if let cgImage, result == .succeeded {
                    // This is a rough ordering; actual timestamp is in actualTime
                }
                if result == .failed, let error {
                    errors.append(error)
                }
                progressHandler(completed, times.count)
                if completed == times.count {
                    if errors.count == times.count {
                        continuation.resume(throwing: errors[0])
                    } else {
                        continuation.resume(returning: Array(images.values))
                    }
                }
            }
        }
    }
}
