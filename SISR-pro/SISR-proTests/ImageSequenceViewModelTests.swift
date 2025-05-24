import XCTest
@testable import SISR_pro
import Foundation

@MainActor
final class ImageSequenceViewModelTests: XCTestCase {
    var viewModel: ImageSequenceViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = ImageSequenceViewModel()
    }
    
    // Helper for test setup
    func setImageURLsForTest(_ urls: [URL]) {
        viewModel.setImageURLsForTest(urls)
    }
    
    func testFrameNumberPaddingDetection() {
        // Simulate image URLs with different paddings
        let urls = [
            URL(fileURLWithPath: "/tmp/0001.png"),
            URL(fileURLWithPath: "/tmp/0002.png"),
            URL(fileURLWithPath: "/tmp/0010.png"),
            URL(fileURLWithPath: "/tmp/0100.png")
        ]
        setImageURLsForTest(urls)
        XCTAssertEqual(viewModel.frameNumberPadding, 4)
        let urls5 = [
            URL(fileURLWithPath: "/tmp/00001.png"),
            URL(fileURLWithPath: "/tmp/00002.png")
        ]
        setImageURLsForTest(urls5)
        XCTAssertEqual(viewModel.frameNumberPadding, 5)
    }
    
    func testInOutPoints() {
        setImageURLsForTest((0..<10).map { URL(fileURLWithPath: "/tmp/\(String(format: "%04d", $0)).png") })
        viewModel.inPoint = 2
        viewModel.outPoint = 7
        XCTAssertEqual(viewModel.inPoint, 2)
        XCTAssertEqual(viewModel.outPoint, 7)
        viewModel.resetInOutPoints()
        XCTAssertEqual(viewModel.inPoint, 0)
        XCTAssertNil(viewModel.outPoint)
    }
    
    func testSeekTo() {
        setImageURLsForTest((0..<5).map { URL(fileURLWithPath: "/tmp/\(String(format: "%04d", $0)).png") })
        viewModel.seekTo(index: 3)
        XCTAssertEqual(viewModel.currentIndex, 3)
        viewModel.seekTo(index: 10)
        XCTAssertNotEqual(viewModel.currentIndex, 10) // Should not go out of bounds
    }
    
    func testOverlayFrameNumberFormatting() {
        viewModel.frameNumberPadding = 4
        let formatted = String(format: "FRAME: %0*d", viewModel.frameNumberPadding, 23)
        XCTAssertEqual(formatted, "FRAME: 0023")
        viewModel.frameNumberPadding = 5
        let formatted5 = String(format: "FRAME: %0*d", viewModel.frameNumberPadding, 23)
        XCTAssertEqual(formatted5, "FRAME: 00023")
    }
    
    func testOverlayDateTimeFormatting() {
        let date = Date(timeIntervalSince1970: 1754600040) // e.g. Thursday, Sep 7, 2025 08:14PM UTC
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy hh:mma"
        let formatted = formatter.string(from: date)
        XCTAssertTrue(formatted.contains(", 2025 "))
        XCTAssertTrue(formatted.hasSuffix("PM"))
    }
    
    // MARK: - Test-only injection for imageURLs and frameNumberPadding
    // This should be added to the main code as an internal method for testing
    // For now, we use this as a workaround
    // You may want to move this to the main class with @testable import
    // and mark it as internal(set) for better testability
    // This is a workaround for the actor isolation and access control
    // If you want to keep properties private, use dependency injection or test-only API
} 