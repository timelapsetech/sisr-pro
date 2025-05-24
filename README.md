# Simple Image Sequence Renderer (SISR) -- Pro Edition

**SISR PRO** v0.1.0

A modern, macOS-native application for fast, flexible, and professional image sequence rendering. Designed for creators, animators, and video professionals who need robust cropping, preview, and export tools for image sequences.

---

## Features

- **Modern macOS UI**: Dark, sleek, and responsive interface with grouped controls and large preview.
- **Image Sequence Loading**: Supports PNG and JPG sequences, with automatic frame number detection and padding.
- **Interactive Cropping**: Draw and preview crop areas with aspect ratio constraints (Free, 16:9, 4:3, 9:16).
- **Timeline Navigation**: Quickly scan through long sequences with a slider and navigation buttons.
- **In/Out Range Selection**: Set in/out points visually or by number for partial renders.
- **Flexible Output**:
  - Image sequence (PNG)
  - MP4 video (H.264)
  - ProRes 422 video (MOV)
  - HD/UHD/Native resolution options (with auto-scaling)
- **Overlay Options**:
  - Frame number (auto-padded, top center)
  - Date/time (from EXIF or file, bottom right)
- **Smart Output Naming**: Output files are named based on input folder and render options for easy organization.
- **macOS Native**: Built with SwiftUI, AVFoundation, and AppKit for best performance and integration.

![SISR PRO Screenshot](Resources/sisr-pro-screenshot.png)

---

## Installation & Building

### Requirements
- macOS 12.0 or later
- Xcode 14.0 or later
- Swift 5.7 or later

### Build Instructions
1. Clone this repository:
   ```sh
   git clone https://github.com/timelapsetech/sisr-pro.git
   cd sisr-pro/SISR-pro
   ```
2. Open `SISR-pro.xcodeproj` in Xcode.
3. Build and run the project (⌘R).

---

## Usage

1. **Select Source Directory**: Click the folder icon and choose a directory containing your image sequence (PNG/JPG, numbered).
2. **Preview & Crop**: Use the large preview to draw/select your crop area. Adjust aspect ratio as needed.
3. **Set In/Out Points**: Use the slider, navigation, or number fields to set your render range.
4. **Choose Output Options**: Select format, resolution, overlays, and output directory.
5. **Render**: Click the Render button. Progress and errors are shown below.
6. **Find Output**: Output files are named for easy identification and saved in your chosen directory.

---

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change or add.

- Please follow the existing code style and add tests for new features.
- See [CONTRIBUTING.md](CONTRIBUTING.md) for more details (create this file if you want to encourage contributions).

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Credits

- Developed by [Your Name or Organization]
- Inspired by the needs of animators, VFX, and video professionals.

---

## Version

**SISR PRO v0.1.0**

---

## Contact

For questions, suggestions, or support, please open an issue on GitHub or contact [info@timelapsetech.com]. 