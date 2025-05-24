import SwiftUI

struct ImagePreviewView: View {
    let image: NSImage?
    @Binding var cropRect: CGRect
    let aspectRatio: AspectRatio
    
    @State private var imageSize: CGSize = .zero
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var dragEnd: CGPoint = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    let displaySize = calculateDisplaySize(imageSize: image.size, containerSize: geometry.size)
                    let displayOrigin = CGPoint(
                        x: (geometry.size.width - displaySize.width) / 2,
                        y: (geometry.size.height - displaySize.height) / 2
                    )
                    let displayFrame = CGRect(origin: displayOrigin, size: displaySize)
                    
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(x: displayFrame.midX, y: displayFrame.midY)
                        .onAppear {
                            imageSize = image.size
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Text("No Image Selected")
                                .foregroundColor(.secondary)
                        )
                }
                
                // Crop overlay
                if isDragging || !cropRect.isEmpty {
                    let displaySize = image != nil ? calculateDisplaySize(imageSize: image!.size, containerSize: geometry.size) : .zero
                    let displayOrigin = CGPoint(
                        x: (geometry.size.width - displaySize.width) / 2,
                        y: (geometry.size.height - displaySize.height) / 2
                    )
                    let displayFrame = CGRect(origin: displayOrigin, size: displaySize)
                    let screenRect = isDragging ? calculateScreenRect(displayFrame: displayFrame) : convertToScreenSpace(cropRect, displayFrame: displayFrame)
                    CropOverlay(rect: screenRect)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStart = value.location
                        }
                        dragEnd = value.location
                    }
                    .onEnded { _ in
                        isDragging = false
                        let displaySize = image != nil ? calculateDisplaySize(imageSize: image!.size, containerSize: geometry.size) : .zero
                        let displayOrigin = CGPoint(
                            x: (geometry.size.width - displaySize.width) / 2,
                            y: (geometry.size.height - displaySize.height) / 2
                        )
                        let displayFrame = CGRect(origin: displayOrigin, size: displaySize)
                        let screenRect = calculateScreenRect(displayFrame: displayFrame)
                        cropRect = convertToImageSpace(screenRect, displayFrame: displayFrame)
                    }
            )
        }
    }
    
    private func calculateDisplaySize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        if imageAspect > containerAspect {
            // Image is wider than container
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image is taller than container
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
    
    private func calculateScreenRect(displayFrame: CGRect) -> CGRect {
        let start = dragStart
        let end = dragEnd
        
        var rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        
        // Constrain to image bounds
        rect = rect.intersection(displayFrame)
        
        if let ratio = aspectRatio.ratio, rect.height > 0 {
            let currentRatio = rect.width / rect.height
            if currentRatio > ratio {
                // Too wide, adjust height
                let newHeight = rect.width / ratio
                rect.size.height = newHeight
                rect.origin.y = rect.midY - newHeight/2
            } else {
                // Too tall, adjust width
                let newWidth = rect.height * ratio
                rect.size.width = newWidth
                rect.origin.x = rect.midX - newWidth/2
            }
            rect = rect.intersection(displayFrame)
        }
        return rect
    }
    
    private func convertToImageSpace(_ screenRect: CGRect, displayFrame: CGRect) -> CGRect {
        guard displayFrame.width > 0, imageSize.width > 0 else { return .zero }
        let scaleX = imageSize.width / displayFrame.width
        let scaleY = imageSize.height / displayFrame.height
        let x = (screenRect.origin.x - displayFrame.origin.x) * scaleX
        let y = (screenRect.origin.y - displayFrame.origin.y) * scaleY
        let width = screenRect.width * scaleX
        let height = screenRect.height * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func convertToScreenSpace(_ imageRect: CGRect, displayFrame: CGRect) -> CGRect {
        guard imageSize.width > 0, displayFrame.width > 0 else { return .zero }
        let scaleX = displayFrame.width / imageSize.width
        let scaleY = displayFrame.height / imageSize.height
        let x = displayFrame.origin.x + (imageRect.origin.x * scaleX)
        let y = displayFrame.origin.y + (imageRect.origin.y * scaleY)
        let width = imageRect.width * scaleX
        let height = imageRect.height * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct CropOverlay: View {
    let rect: CGRect
    
    var body: some View {
        Rectangle()
            .stroke(Color.white, lineWidth: 2)
            .background(Color.black.opacity(0.3))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

#Preview {
    ImagePreviewView(
        image: nil,
        cropRect: .constant(.zero),
        aspectRatio: .free
    )
    .frame(width: 400, height: 300)
} 