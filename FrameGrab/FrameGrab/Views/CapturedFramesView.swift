import SwiftUI
import Photos

struct CapturedFramesView: View {
    @ObservedObject var viewModel: VideoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFrame: CapturedFrame?
    @State private var saveAllInProgress = false
    @State private var saveStatus: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.capturedFrames.isEmpty {
                    ContentUnavailableView(
                        "No Frames Captured",
                        systemImage: "camera.viewfinder",
                        description: Text("Use the Capture Frame button while scrubbing the video")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(viewModel.capturedFrames) { frame in
                                FrameThumbnailCell(
                                    frame: frame,
                                    onTap: { selectedFrame = frame },
                                    onSave: { saveFrame(frame) },
                                    onDelete: { deleteFrame(frame) }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(viewModel.capturedFrames.count) Frame\(viewModel.capturedFrames.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                if !viewModel.capturedFrames.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await saveAllFrames() }
                        } label: {
                            if saveAllInProgress {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Label("Save All", systemImage: "square.and.arrow.down.on.square")
                            }
                        }
                        .disabled(saveAllInProgress)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let status = saveStatus {
                    Text(status)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation { saveStatus = nil }
                            }
                        }
                }
            }
        }
        .sheet(item: $selectedFrame) { frame in
            FrameDetailView(frame: frame, onSave: { saveFrame(frame) })
        }
    }

    private func saveFrame(_ frame: CapturedFrame) {
        Task {
            do {
                try await requestPhotosPermission()
                try await frame.saveToPhotos()
                withAnimation { saveStatus = "Saved to Photos" }
            } catch {
                withAnimation { saveStatus = "Save failed: \(error.localizedDescription)" }
            }
        }
    }

    private func saveAllFrames() async {
        saveAllInProgress = true
        do {
            try await requestPhotosPermission()
            var saved = 0
            for frame in viewModel.capturedFrames {
                try await frame.saveToPhotos()
                saved += 1
            }
            withAnimation { saveStatus = "Saved \(saved) frames to Photos" }
        } catch {
            withAnimation { saveStatus = "Save failed: \(error.localizedDescription)" }
        }
        saveAllInProgress = false
    }

    private func deleteFrame(_ frame: CapturedFrame) {
        withAnimation {
            viewModel.capturedFrames.removeAll { $0.id == frame.id }
        }
    }

    private func requestPhotosPermission() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PermissionError.photosAccessDenied
        }
    }
}

// MARK: - Frame Thumbnail Cell

struct FrameThumbnailCell: View {
    let frame: CapturedFrame
    let onTap: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: frame.image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, maxHeight: 150)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(frame.formattedTimestamp)
                    .font(.system(.caption2, design: .monospaced).bold())
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .contextMenu {
            Button {
                onSave()
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Frame Detail View

struct FrameDetailView: View {
    let frame: CapturedFrame
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Image(uiImage: frame.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1.0, min(value, 5.0))
                            }
                            .onEnded { _ in
                                if scale < 1.0 {
                                    withAnimation(.spring) { scale = 1.0; offset = .zero }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 { offset = value.translation }
                            }
                            .onEnded { _ in
                                if scale <= 1.0 {
                                    withAnimation(.spring) { offset = .zero }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring) {
                            scale = scale > 1.0 ? 1.0 : 2.5
                            if scale <= 1.0 { offset = .zero }
                        }
                    }
            }
            .background(Color.black)
            .navigationTitle(frame.formattedTimestamp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .tint(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onSave()
                        dismiss()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .tint(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Errors

enum PermissionError: LocalizedError {
    case photosAccessDenied

    var errorDescription: String? {
        switch self {
        case .photosAccessDenied:
            return "Photos access was denied. Please enable it in Settings."
        }
    }
}
