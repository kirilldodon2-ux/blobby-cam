import CoreMedia
import CoreVideo
import ImageIO

struct CameraFrame {
    let pixelBuffer: CVPixelBuffer
    /// Timestamp from the captured sample, represented in CoreMedia's media-timebase type.
    let timestamp: CMTime
    let orientation: CGImagePropertyOrientation
    let isMirrored: Bool
}
