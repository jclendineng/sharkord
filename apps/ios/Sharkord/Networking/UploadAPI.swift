import Foundation
import UniformTypeIdentifiers

// mirrors apps/client/src/helpers/upload-file.ts: the body is the raw file, everything else rides in
// headers, and the name is percent-encoded because a header cannot carry non latin-1 text
enum UploadAPI {
    private struct ErrorResponse: Decodable {
        let error: String
    }

    static func upload(fileAt fileURL: URL, name: String, to address: ServerAddress, token: String) async throws -> TemporaryFile {
        let mimeType = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"

        var request = URLRequest(url: address.url(path: "upload"))
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "x-file-type")
        request.setValue(token, forHTTPHeaderField: "x-token")
        request.setValue(
            name.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlUnreservedAllowed),
            forHTTPHeaderField: "x-file-name"
        )

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                ?? "Upload failed with status \(http.statusCode)."

            throw AuthAPI.RequestError(message: message)
        }

        return try JSONDecoder().decode(TemporaryFile.self, from: data)
    }
}

private extension CharacterSet {
    // what encodeURIComponent leaves alone, so the server's decodeURIComponent restores the exact name
    static let urlUnreservedAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
}
