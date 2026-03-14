import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = VideoViewModel()
    @State private var photosItem: PhotosPickerItem?
    @State private var showingCapturedFrames = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.videoURL != nil {
                    FrameScrubbingView(viewModel: viewModel)
                } else {
                    WelcomeView()
                }
            }
            .navigationTitle("FrameGrab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    PhotosPicker(
                        selection: $photosItem,
                        matching: .videos
                    ) {
                        Label("Pick Video", systemImage: "video.badge.plus")
                    }
                }

                if viewModel.videoURL != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingCapturedFrames = true
                        } label: {
                            Label("Frames", systemImage: "photo.stack")
                                .overlay(alignment: .topTrailing) {
                                    if !viewModel.capturedFrames.isEmpty {
                                        Text("\(viewModel.capturedFrames.count)")
                                            .font(.caption2.bold())
                                            .padding(4)
                                            .background(Color.accentColor)
                                            .clipShape(Circle())
                                            .foregroundStyle(.white)
                                            .offset(x: 8, y: -8)
                                    }
                                }
                        }
                    }
                }
            }
            .onChange(of: photosItem) { _, newItem in
                Task {
                    await viewModel.loadVideo(from: newItem)
                }
            }
            .sheet(isPresented: $showingCapturedFrames) {
                CapturedFramesView(viewModel: viewModel)
            }
        }
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "film.stack")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("FrameGrab")
                    .font(.largeTitle.bold())
                Text("Scrub any video and capture\nfull-resolution frames")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "video.badge.plus",  text: "Import from Photos or Files")
                FeatureRow(icon: "slider.horizontal.3", text: "Frame-accurate scrubbing")
                FeatureRow(icon: "camera.viewfinder",  text: "Capture full-resolution frames")
                FeatureRow(icon: "square.and.arrow.down", text: "Save directly to Photos")
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
