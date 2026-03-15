import UIKit
import Photos

struct CapturedFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let timestamp: Double
    var isSaved = false

    var formattedTimestamp: String {
        let total = Int(timestamp)
        let minutes = total / 60
        let seconds = total % 60
        let millis = Int((timestamp - Double(total)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }

    func saveToPhotos() async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: self.image)
        }
    }
}
