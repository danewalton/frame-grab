# FrameGrab

A SwiftUI iPhone app for scrubbing through videos and capturing full-resolution frames — no more low-quality screenshots.

## Requirements

- Xcode 15+
- iOS 17.0+
- A physical iPhone (camera roll / Photos access required for saving)

## Getting Started

1. Clone the repo and open `FrameGrab/FrameGrab.xcodeproj` in Xcode
2. Select your iPhone as the run destination
3. Build & run (`⌘R`)
4. When prompted, grant **Photos** access so the app can import videos and save frames

## Usage

### Import a video
Tap the **video camera icon** (top-left toolbar) to open the system Photos picker. Select any video from your library.

### Scrub to the frame you want
- **Drag** anywhere on the thumbnail strip to jump to that point in the video
- Tap **⏮ / ⏭** (frame-step buttons) to step back or forward one frame at a time using the video's native frame rate
- Tap the **play/pause** button for normal playback; scrubbing pauses automatically

### Capture a frame
Tap **Capture Frame**. A brief shutter flash confirms the capture. The button is disabled while extraction is in progress.

### Review and save captured frames
Tap the **photo stack icon** (top-right toolbar) — the badge shows how many frames you've captured.

- **Tap** any thumbnail to open a full-screen detail view
- In the detail view, **pinch** or **double-tap** to zoom and pan
- Tap **Save** (detail view) or long-press a thumbnail and choose **Save to Photos** to save a single frame
- Tap **Save All** to export every captured frame to your Photos library at once
- Long-press → **Delete** to remove a frame from the session

Frames are saved at the video's native resolution — not screen resolution.

---

## Architecture

```
FrameGrab/
├── FrameGrabApp.swift          # @main entry point
├── ContentView.swift           # Root NavigationStack, PhotosPicker toolbar,
│                               # welcome screen, sheet presentation
├── Info.plist                  # NSPhotoLibrary usage descriptions
├── Assets.xcassets/
│
├── Views/
│   ├── FrameScrubbingView.swift    # Main scrubbing screen
│   │   ├── VideoPlayerLayer        # UIViewRepresentable → AVPlayerLayer
│   │   ├── ThumbnailScrubber       # Drag-gesture scrub bar with playhead
│   │   └── ThumbnailStrip          # Evenly-spaced thumbnail images
│   │
│   └── CapturedFramesView.swift    # Captured frames grid
│       ├── FrameThumbnailCell      # Grid cell with timestamp + context menu
│       └── FrameDetailView         # Full-screen zoom/pan detail sheet
│
├── ViewModels/
│   └── VideoViewModel.swift        # @MainActor ObservableObject
│       ├── loadVideo(from:)        # PhotosPickerItem → temp file → AVURLAsset
│       ├── seek(to:)               # Zero-tolerance CMTime seek
│       ├── stepFrame(forward:)     # ±1 frame via nominalFrameRate
│       ├── togglePlayback()        # play/pause with end-of-video guard
│       ├── captureCurrentFrame()   # delegates to FrameExtractor actor
│       └── generateThumbnailStrip()# 20 thumbnails built concurrently
│
└── Services/
    ├── FrameExtractor.swift        # Swift actor wrapping AVAssetImageGenerator
    │                               # toleranceBefore/After: .zero for exact frames
    │                               # appliesPreferredTrackTransform for correct rotation
    └── CapturedFrame.swift         # Value type: UIImage + timestamp + save logic
                                    # PHPhotoLibrary.performChanges for async save
```

### Data flow

```
PhotosPicker → VideoViewModel.loadVideo()
                    │
                    ├─→ AVURLAsset → AVPlayer → VideoPlayerLayer (display)
                    └─→ generateThumbnailStrip() → thumbnailCache [@Published]
                                                        │
                                               ThumbnailStrip renders

User drags scrubber → VideoViewModel.seek() → AVPlayer.seek(toleranceBefore: .zero)

User taps "Capture Frame"
    → VideoViewModel.captureCurrentFrame()
        → FrameExtractor.extractFrame(asset, at: currentTime)
            → AVAssetImageGenerator.image(at:)   ← full resolution, exact frame
        → CapturedFrame appended to capturedFrames [@Published]

User taps "Save" → CapturedFrame.saveToPhotos()
    → PHPhotoLibrary.performChanges { PHAssetChangeRequest }
```

### Key technical decisions

| Decision | Reason |
|---|---|
| `AVAssetImageGenerator` with `toleranceBefore/After: .zero` | Guarantees the exact frame at the requested timestamp, not the nearest keyframe |
| `appliesPreferredTrackTransform = true` | Respects the video's rotation metadata so portrait/landscape frames are oriented correctly |
| `FrameExtractor` as a Swift `actor` | Serialises image generation calls; `AVAssetImageGenerator` is not thread-safe |
| `VideoViewModel` annotated `@MainActor` | All `@Published` mutations happen on the main thread without explicit `DispatchQueue.main` calls |
| `VideoTransferable` / `FileRepresentation` | Copies the picked video to a temp directory so the app retains access after the picker dismisses |
| Thumbnail strip built with `withTaskGroup` | All 20 thumbnails are requested concurrently; each resolves independently without blocking the UI |
