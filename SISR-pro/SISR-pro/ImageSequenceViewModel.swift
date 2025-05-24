import SwiftUI
import AVFoundation

@MainActor
class ImageSequenceViewModel: ObservableObject {
    @Published var sourceDirectory: URL?
    @Published var outputDirectory: URL?
    @Published var currentImage: NSImage?
    @Published var cropRect: CGRect = .zero
    @Published var outputFormat: OutputFormat = .imageSequence
    @Published var errorMessage: String?
    @Published var outputResolution: OutputResolution = .native
    @Published var inPoint: Int = 0
    @Published var outPoint: Int? = nil // nil means last frame
    @Published var overlayFrameNumber: Bool = false
    @Published var overlayDateTime: Bool = false
    @Published var selectedAspectRatio: AspectRatio = .free
    
    private var imageURLs: [URL] = []
    private(set) var currentIndex: Int = 0
    private(set) var totalImages: Int = 0
    var frameNumberPadding: Int = 4
    
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < totalImages - 1 }
    var canRender: Bool {
        guard sourceDirectory != nil, outputDirectory != nil, !cropRect.isEmpty else { return false }
        let count = imageURLs.count
        let last = outPoint ?? (count - 1)
        return count > 0 && inPoint >= 0 && last >= inPoint && last < count
    }
    
    func selectSourceDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a directory containing image sequence"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK {
            sourceDirectory = panel.url
            loadImageSequence()
        }
    }
    
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a directory for output files"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK {
            do {
                let url = panel.url!
                // Test write permissions
                let testFile = url.appendingPathComponent(".test_write_permission")
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: testFile)
                
                outputDirectory = url
                errorMessage = nil
            } catch {
                errorMessage = "Cannot write to selected directory: \(error.localizedDescription)"
                outputDirectory = nil
            }
        }
    }
    
    func previousImage() {
        guard canGoPrevious else { return }
        currentIndex -= 1
        loadCurrentImage()
    }
    
    func nextImage() {
        guard canGoNext else { return }
        currentIndex += 1
        loadCurrentImage()
    }
    
    func seekTo(index: Int) {
        guard index >= 0 && index < imageURLs.count else { return }
        currentIndex = index
        loadCurrentImage()
    }
    
    private func loadImageSequence() {
        guard let directory = sourceDirectory else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            
            imageURLs = fileURLs
                .filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            totalImages = imageURLs.count
            currentIndex = 0
            // Detect frame number padding from filenames
            if !imageURLs.isEmpty {
                let regex = try? NSRegularExpression(pattern: "(\\d+)")
                let matches = imageURLs.compactMap { url -> Int? in
                    let name = url.deletingPathExtension().lastPathComponent
                    guard let match = regex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                          let range = Range(match.range(at: 1), in: name) else { return nil }
                    return name[range].count
                }
                if let maxDigits = matches.max(), maxDigits > 0 {
                    frameNumberPadding = maxDigits
                } else {
                    frameNumberPadding = 4
                }
            } else {
                frameNumberPadding = 4
            }
            loadCurrentImage()
        } catch {
            print("Error loading image sequence: \(error)")
        }
    }
    
    private func loadCurrentImage() {
        guard currentIndex < imageURLs.count else { return }
        currentImage = NSImage(contentsOf: imageURLs[currentIndex])
    }
    
    func render(progress: @escaping (Double) -> Void) async {
        print("[DEBUG] Render called")
        let count = imageURLs.count
        let last = outPoint ?? (count - 1)
        if sourceDirectory == nil {
            print("[DEBUG] No source directory selected")
            await MainActor.run { errorMessage = "Cannot render: No source directory selected." }
            return
        }
        if outputDirectory == nil {
            print("[DEBUG] No output directory selected")
            await MainActor.run { errorMessage = "Cannot render: No output directory selected." }
            return
        }
        if cropRect.isEmpty {
            print("[DEBUG] No crop area selected")
            await MainActor.run { errorMessage = "Cannot render: No crop area selected." }
            return
        }
        if count == 0 {
            print("[DEBUG] No images loaded")
            await MainActor.run { errorMessage = "Cannot render: No images loaded." }
            return
        }
        if inPoint < 0 || last < inPoint || last >= count {
            print("[DEBUG] In/Out points are invalid (in: \(inPoint+1), out: \((outPoint != nil ? (outPoint!+1) : count)))")
            await MainActor.run { errorMessage = "Cannot render: In/Out points are invalid (in: \(inPoint+1), out: \((outPoint != nil ? (outPoint!+1) : count))." }
            return
        }
        print("[DEBUG] Starting rendering: outputFormat=\(outputFormat), in=\(inPoint), out=\(last), cropRect=\(cropRect)")
        do {
            switch outputFormat {
            case .imageSequence:
                try await renderImageSequence(progress: progress)
            case .mp4:
                try await renderVideo(useProRes: false, progress: progress)
            case .proRes:
                try await renderVideo(useProRes: true, progress: progress)
            }
            print("[DEBUG] Rendering finished successfully")
        } catch {
            print("[DEBUG] Rendering failed: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Rendering failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func smartOutputFileName(extension ext: String) -> String {
        let folderName = sourceDirectory?.lastPathComponent ?? "output"
        let aspect: String = {
            switch selectedAspectRatio {
            case .ratio16_9: return "16x9"
            case .ratio4_3: return "4x3"
            case .ratio9_16: return "9x16"
            case .free: return "free"
            }
        }()
        let res = outputResolution == .native ? "native" : outputResolution == .hd ? "HD" : outputResolution == .uhd ? "UHD" : ""
        let inStr = String(format: "in%0*d", frameNumberPadding, inPoint + 1)
        let outStr = String(format: "out%0*d", frameNumberPadding, (outPoint ?? (totalImages - 1)) + 1)
        var overlays: [String] = []
        if overlayFrameNumber { overlays.append("frameNum") }
        if overlayDateTime { overlays.append("dateTime") }
        let overlayStr = overlays.isEmpty ? "" : "_" + overlays.joined(separator: "_")
        return "\(folderName)_\(aspect)_\(res)_\(inStr)-\(outStr)\(overlayStr).\(ext)"
    }
    
    private func renderImageSequence(progress: @escaping (Double) -> Void) async throws {
        guard let outputDir = outputDirectory else {
            throw NSError(domain: "ImageSequenceViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No output directory selected"])
        }
        
        // Create output directory if it doesn't exist
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        let lastFrame = (outPoint ?? (imageURLs.count - 1))
        let renderRange = inPoint...lastFrame
        let totalToRender = renderRange.count
        var renderedCount = 0
        let prefix = smartOutputFileName(extension: "png").replacingOccurrences(of: ".png", with: "")
        for index in renderRange {
            let url = imageURLs[index]
            guard let image = NSImage(contentsOf: url) else {
                print("Failed to load image at: \(url.path)")
                continue
            }
            var croppedImage = cropImage(image)
            if let targetSize = outputResolution.size {
                croppedImage = resizeImage(croppedImage, to: targetSize)
            }
            if overlayFrameNumber {
                croppedImage = overlayFrameNumberOnImage(croppedImage, frameNumber: index + 1)
            }
            if overlayDateTime {
                let date = extractImageDate(url: url)
                croppedImage = overlayDateTimeOnImage(croppedImage, date: date)
            }
            let outputURL = outputDir.appendingPathComponent("\(prefix)_frame_\(String(format: "%0*d", frameNumberPadding, index + 1)).png")
            guard let tiffData = croppedImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                print("Failed to convert image to PNG at index: \(index)")
                continue
            }
            do {
                try pngData.write(to: outputURL)
                print("Successfully wrote frame to: \(outputURL.path)")
            } catch {
                print("Failed to write frame to \(outputURL.path): \(error)")
                throw error
            }
            renderedCount += 1
            await MainActor.run {
                progress(Double(renderedCount) / Double(totalToRender))
            }
        }
    }
    
    private func renderVideo(useProRes: Bool, progress: @escaping (Double) -> Void) async throws {
        guard let outputDir = outputDirectory else {
            throw NSError(domain: "ImageSequenceViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No output directory selected"])
        }
        
        // Create output directory if it doesn't exist
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        let ext = useProRes ? "mov" : "mp4"
        let outputURL = outputDir.appendingPathComponent(smartOutputFileName(extension: ext))
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Test write permissions
        do {
            let testFile = outputDir.appendingPathComponent(".test_write_permission")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
        } catch {
            throw NSError(domain: "ImageSequenceViewModel", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot write to output directory: \(error.localizedDescription)"])
        }
        
        // Create AVAssetWriter
        guard let assetWriter = try? AVAssetWriter(url: outputURL, fileType: useProRes ? .mov : .mp4) else {
            throw NSError(domain: "ImageSequenceViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create video writer"])
        }
        
        let videoSize: CGSize = outputResolution.size ?? CGSize(width: cropRect.width, height: cropRect.height)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: useProRes ? AVVideoCodecType.proRes422 : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height)
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true
        
        if !assetWriter.canAdd(writerInput) {
            throw NSError(domain: "ImageSequenceViewModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to writer"])
        }
        
        assetWriter.add(writerInput)
        
        // Start writing
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        let frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        
        let lastFrame = (outPoint ?? (imageURLs.count - 1))
        let renderRange = inPoint...lastFrame
        let totalToRender = renderRange.count
        var renderedCount = 0
        for (i, index) in renderRange.enumerated() {
            let url = imageURLs[index]
            guard let image = NSImage(contentsOf: url) else {
                print("Failed to load image at: \(url.path)")
                continue
            }
            var croppedImage = cropImage(image)
            if let targetSize = outputResolution.size {
                croppedImage = resizeImage(croppedImage, to: targetSize)
            }
            if overlayFrameNumber {
                croppedImage = overlayFrameNumberOnImage(croppedImage, frameNumber: index + 1)
            }
            if overlayDateTime {
                let date = extractImageDate(url: url)
                croppedImage = overlayDateTimeOnImage(croppedImage, date: date)
            }
            
            // Convert image to pixel buffer
            guard let pixelBuffer = createPixelBuffer(from: croppedImage) else {
                print("Failed to create pixel buffer for image at index: \(index)")
                continue
            }
            
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            
            // Create sample buffer
            var sampleBuffer: CMSampleBuffer?
            var timingInfo = CMSampleTimingInfo(
                duration: frameDuration,
                presentationTimeStamp: presentationTime,
                decodeTimeStamp: presentationTime
            )
            
            var formatDescription: CMFormatDescription?
            let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription
            )
            
            guard formatStatus == noErr, let formatDescription = formatDescription else {
                print("Failed to create format description for image at index: \(index)")
                continue
            }
            
            let sampleStatus = CMSampleBufferCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDescription,
                sampleTiming: &timingInfo,
                sampleBufferOut: &sampleBuffer
            )
            
            guard sampleStatus == noErr, let sampleBuffer = sampleBuffer else {
                print("Failed to create sample buffer for image at index: \(index)")
                continue
            }
            
            // Wait for the writer input to be ready
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Append the sample buffer
            if !writerInput.append(sampleBuffer) {
                if let error = assetWriter.error {
                    print("Failed to append sample buffer at index \(index): \(error)")
                    throw error
                }
            }
            
            renderedCount += 1
            await MainActor.run {
                progress(Double(renderedCount) / Double(totalToRender))
            }
        }
        
        // Finish writing
        writerInput.markAsFinished()
        await assetWriter.finishWriting()
        
        // Verify the output file exists and has content
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(domain: "ImageSequenceViewModel", code: 4, userInfo: [NSLocalizedDescriptionKey: "Output file was not created"])
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        guard let fileSize = attributes[.size] as? UInt64, fileSize > 0 else {
            throw NSError(domain: "ImageSequenceViewModel", code: 5, userInfo: [NSLocalizedDescriptionKey: "Output file is empty"])
        }
        
        print("Successfully created video at: \(outputURL.path) with size: \(fileSize) bytes")
    }
    
    private func createPixelBuffer(from image: NSImage) -> CVPixelBuffer? {
        let width = Int(cropRect.width)
        let height = Int(cropRect.height)
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        
        // Draw the image into the pixel buffer
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: rect)
        
        return buffer
    }
    
    private func cropImage(_ image: NSImage) -> NSImage {
        // Flip the cropRect vertically to match CoreGraphics coordinate system
        let imageHeight = image.size.height
        let flippedCropRect = CGRect(
            x: cropRect.origin.x,
            y: imageHeight - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )
        let croppedImage = NSImage(size: flippedCropRect.size)
        croppedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: flippedCropRect.size),
            from: flippedCropRect,
            operation: .copy,
            fraction: 1.0
        )
        croppedImage.unlockFocus()
        return croppedImage
    }
    
    private func resizeImage(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    private func overlayFrameNumberOnImage(_ image: NSImage, frameNumber: Int) -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        // Draw frame number
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let fontSize = image.size.height * 0.06 // 6% of height
        let font = NSFont(name: "Menlo", size: fontSize) ?? NSFont(name: "Courier", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .strokeColor: NSColor.black,
            .strokeWidth: -2.0
        ]
        let text = String(format: "FRAME: %0*ld", frameNumberPadding, frameNumber)
        let textSize = text.size(withAttributes: attributes)
        let safeTop = image.size.height * 0.10 // 10% from top
        let padding: CGFloat = fontSize * 0.5
        let boxRect = NSRect(
            x: (image.size.width - textSize.width) / 2 - padding / 2,
            y: image.size.height - safeTop - textSize.height - padding / 2,
            width: textSize.width + padding,
            height: textSize.height + padding
        )
        // Draw semi-transparent rounded rectangle
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: padding * 0.4, yRadius: padding * 0.4)
        NSColor.black.withAlphaComponent(0.6).setFill()
        boxPath.fill()
        // Draw the text
        let textRect = NSRect(
            x: (image.size.width - textSize.width) / 2,
            y: image.size.height - safeTop - textSize.height,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        newImage.unlockFocus()
        return newImage
    }
    
    private func extractImageDate(url: URL) -> Date? {
        // Try EXIF first
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        // Fallback to file creation date
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.creationDate] as? Date {
            return date
        }
        return nil
    }
    
    private func overlayDateTimeOnImage(_ image: NSImage, date: Date?) -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        guard let date = date else {
            newImage.unlockFocus(); return newImage
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let fontSize = image.size.height * 0.045 // slightly smaller than frame overlay
        let font = NSFont(name: "Menlo", size: fontSize) ?? NSFont(name: "Courier", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .strokeColor: NSColor.black,
            .strokeWidth: -2.0
        ]
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy hh:mma"
        let text = formatter.string(from: date)
        let textSize = text.size(withAttributes: attributes)
        let safeRight = image.size.width * 0.02
        let safeBottom = image.size.height * 0.08
        let padding: CGFloat = fontSize * 0.5
        let boxRect = NSRect(
            x: image.size.width - safeRight - textSize.width - padding / 2,
            y: safeBottom - padding / 2,
            width: textSize.width + padding,
            height: textSize.height + padding
        )
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: padding * 0.4, yRadius: padding * 0.4)
        NSColor.black.withAlphaComponent(0.6).setFill()
        boxPath.fill()
        let textRect = NSRect(
            x: image.size.width - safeRight - textSize.width,
            y: safeBottom,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        newImage.unlockFocus()
        return newImage
    }
    
    func setInPoint() {
        inPoint = currentIndex
        if let out = outPoint, inPoint > out {
            outPoint = inPoint
        }
    }
    
    func setOutPoint() {
        outPoint = currentIndex
        if inPoint > (outPoint ?? inPoint) {
            inPoint = outPoint ?? inPoint
        }
    }
    
    func resetInOutPoints() {
        inPoint = 0
        outPoint = nil
    }

#if DEBUG
    @MainActor
    internal func setImageURLsForTest(_ urls: [URL]) {
        self.imageURLs = urls
        self.totalImages = urls.count
        self.currentIndex = 0
        // Simulate frame number padding detection
        if !urls.isEmpty {
            let regex = try? NSRegularExpression(pattern: "(\\d+)")
            let matches = urls.compactMap { url -> Int? in
                let name = url.deletingPathExtension().lastPathComponent
                guard let match = regex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                      let range = Range(match.range(at: 1), in: name) else { return nil }
                return name[range].count
            }
            if let maxDigits = matches.max(), maxDigits > 0 {
                frameNumberPadding = maxDigits
            } else {
                frameNumberPadding = 4
            }
        } else {
            frameNumberPadding = 4
        }
    }
#endif
}

enum OutputResolution: String, CaseIterable, Identifiable {
    case native = "Native"
    case hd = "HD (1920x1080)"
    case uhd = "UHD (3840x2160)"
    
    var id: String { rawValue }
    var description: String { rawValue }
    var size: CGSize? {
        switch self {
        case .native: return nil
        case .hd: return CGSize(width: 1920, height: 1080)
        case .uhd: return CGSize(width: 3840, height: 2160)
        }
    }
} 