import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension PhotosPickerItem {
    // avatars and server icons are still pictures, the server turns a gif down too
    func refuseGIF() throws {
        if supportedContentTypes.contains(.gif) {
            throw AuthAPI.RequestError(message: String(localized: "GIFs can't be used here."))
        }
    }
}
