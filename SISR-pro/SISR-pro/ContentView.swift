import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = ImageSequenceViewModel()
    @State private var isRendering = false
    @State private var renderProgress: Double = 0
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Top: Large Image Preview, Navigation, Timeline
            VStack(spacing: 0) {
                ImagePreviewView(
                    image: viewModel.currentImage,
                    cropRect: $viewModel.cropRect,
                    aspectRatio: viewModel.selectedAspectRatio
                )
                .frame(maxWidth: .infinity, maxHeight: 520)
                .background(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.98))
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.top, 24)
                // Navigation Controls
                HStack(spacing: 16) {
                    Button(action: viewModel.previousImage) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentIndex <= 0)
                    Text("\(viewModel.currentIndex + 1) / \(viewModel.totalImages)")
                        .frame(width: 100)
                    Button(action: viewModel.nextImage) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentIndex >= viewModel.totalImages - 1)
                }
                .padding(.vertical, 12)
                .foregroundColor(.white)
                // Timeline Slider
                if viewModel.totalImages > 1 {
                    HStack {
                        Text("1")
                        Slider(value: Binding(
                            get: { Double(viewModel.currentIndex) },
                            set: { newValue in viewModel.seekTo(index: Int(newValue)) }
                        ), in: 0...Double(viewModel.totalImages - 1), step: 1)
                        .frame(maxWidth: 500)
                        Text("\(viewModel.totalImages)")
                    }
                    .padding(.bottom, 8)
                    .foregroundColor(.white)
                }
                // Range (In/Out) Controls
                HStack(spacing: 16) {
                    GroupBox(label: Label("Range", systemImage: "scissors").foregroundColor(.white)) {
                        HStack(spacing: 8) {
                            Text("In:")
                            TextField("In", value: Binding(
                                get: { viewModel.inPoint + 1 },
                                set: { newValue in
                                    let v = max(1, min(newValue, viewModel.totalImages)) - 1
                                    viewModel.inPoint = v
                                    if let out = viewModel.outPoint, v > out { viewModel.outPoint = v }
                                }), formatter: NumberFormatter())
                                .frame(width: 50)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button("Set In") { viewModel.setInPoint() }
                                .disabled(viewModel.currentIndex == viewModel.inPoint)
                            Text("Out:")
                            TextField("Out", value: Binding(
                                get: { (viewModel.outPoint ?? (viewModel.totalImages - 1)) + 1 },
                                set: { newValue in
                                    let v = max(1, min(newValue, viewModel.totalImages)) - 1
                                    viewModel.outPoint = v
                                    if viewModel.inPoint > v { viewModel.inPoint = v }
                                }), formatter: NumberFormatter())
                                .frame(width: 50)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button("Set Out") { viewModel.setOutPoint() }
                                .disabled(viewModel.currentIndex == (viewModel.outPoint ?? (viewModel.totalImages - 1)))
                            Button("Reset In/Out") { viewModel.resetInOutPoints() }
                                .disabled(viewModel.inPoint == 0 && (viewModel.outPoint == nil || viewModel.outPoint == viewModel.totalImages - 1))
                        }
                    }
                    .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.85))
                    .cornerRadius(10)
                }
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            Divider().background(Color.white.opacity(0.2))
            // Bottom: Controls grouped horizontally
            HStack(alignment: .top, spacing: 24) {
                // Project Section
                GroupBox(label: Label("Project", systemImage: "folder").foregroundColor(.white)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Source:")
                            Button(action: viewModel.selectSourceDirectory) {
                                Label(viewModel.sourceDirectory?.lastPathComponent ?? "Select", systemImage: "folder")
                            }
                        }
                        HStack {
                            Text("Output:")
                            Button(action: viewModel.selectOutputDirectory) {
                                Label(viewModel.outputDirectory?.lastPathComponent ?? "Select", systemImage: "externaldrive")
                            }
                        }
                    }
                }
                .frame(minWidth: 220)
                .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.85))
                .cornerRadius(10)
                // Render Options Section
                GroupBox(label: Label("Render Options", systemImage: "slider.horizontal.3").foregroundColor(.white)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Aspect Ratio:")
                            Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                                ForEach(AspectRatio.allCases) { ratio in
                                    Text(ratio.description).tag(ratio)
                                }
                            }
                            .frame(width: 300)
                            .controlSize(.large)
                        }
                        HStack {
                            Text("Format:")
                            Picker("Output Format", selection: $viewModel.outputFormat) {
                                ForEach(OutputFormat.allCases) { format in
                                    Text(format.description).tag(format)
                                }
                            }
                            .frame(width: 300)
                            .controlSize(.large)
                        }
                        if viewModel.selectedAspectRatio == .ratio16_9 {
                            HStack {
                                Text("Resolution:")
                                Picker("Output Resolution", selection: $viewModel.outputResolution) {
                                    ForEach(OutputResolution.allCases) { res in
                                        Text(res.description).tag(res)
                                    }
                                }
                                .frame(width: 300)
                                .controlSize(.large)
                            }
                        }
                    }
                }
                .frame(minWidth: 260)
                .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.85))
                .cornerRadius(10)
                // Overlays Section
                GroupBox(label: Label("Overlays", systemImage: "rectangle.on.rectangle.angled").foregroundColor(.white)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Frame Number", isOn: $viewModel.overlayFrameNumber)
                        Toggle("Date/Time", isOn: $viewModel.overlayDateTime)
                    }
                }
                .frame(minWidth: 160)
                .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.85))
                .cornerRadius(10)
                // Render Section
                GroupBox(label: Label("Render", systemImage: "play.circle").foregroundColor(.white)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            isRendering = true
                            renderProgress = 0
                            errorMessage = nil
                            Task {
                                do {
                                    try await viewModel.render(
                                        progress: { progress in
                                            renderProgress = progress
                                        }
                                    )
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isRendering = false
                            }
                        }) {
                            Label("Render", systemImage: "play.fill")
                                .frame(width: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .accentColor(.mint)
                        .disabled(viewModel.sourceDirectory == nil || viewModel.outputDirectory == nil || isRendering)
                        if isRendering {
                            ProgressView(value: renderProgress)
                                .frame(width: 180)
                            Text("\(Int(renderProgress * 100))%")
                        }
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                .frame(minWidth: 180)
                .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.85))
                .cornerRadius(10)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.98))
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 1100, minHeight: 800)
        .background(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.99))
        .accentColor(.mint)
        .foregroundColor(.white)
    }
}

enum AspectRatio: String, CaseIterable, Identifiable {
    case free = "Free"
    case ratio16_9 = "16:9"
    case ratio4_3 = "4:3"
    case ratio9_16 = "9:16"
    
    var id: String { rawValue }
    var description: String { rawValue }
    
    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .ratio16_9: return 16.0/9.0
        case .ratio4_3: return 4.0/3.0
        case .ratio9_16: return 9.0/16.0
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case imageSequence = "Image Sequence"
    case mp4 = "MP4"
    case proRes = "ProRes 422"
    
    var id: String { rawValue }
    var description: String { rawValue }
}

#Preview {
    ContentView()
} 