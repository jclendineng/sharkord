import CoreImage.CIFilterBuiltins
import UIKit

// a qr code for a sign in, drawn sharp at any size with nearest neighbour scaling
enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard
            let output = filter.outputImage,
            let cgImage = CIContext().createCGImage(output, from: output.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
