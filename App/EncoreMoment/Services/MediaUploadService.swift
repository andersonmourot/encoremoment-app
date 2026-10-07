import Foundation
import UniformTypeIdentifiers
import EncoreMomentCore

struct MediaUploadService {
    /// Mirrors the server's `defaultMaxBodySize = "100mb"`.
    static let maxUploadBytes: Int64 = 100 * 1024 * 1024

    private let baseURL: URL
    private let tokenProvider: () -> String?
    private let decoder: JSONDecoder
    private let errorDecoder = JSONDecoder()

    init(baseURL: URL = AppConfig.apiBaseURL, tokenProvider: @escaping () -> String? = { TokenHolder.shared.token }) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Streams the multipart body from a temp file — a 90MB video upload
    /// stays out of memory entirely (`upload(for:fromFile:)` reads from disk).
    func upload(
        fileURL: URL,
        fileExtension: String,
        kind: MediaKind,
        to eventID: UUID,
        thumbnailData: Data? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> MediaItem {
        // Fail fast — don't stream a body the server will reject on arrival.
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            let bodyBytes = Int64(size) + Int64(thumbnailData?.count ?? 0) + 1024
            if bodyBytes > Self.maxUploadBytes {
                throw UploadError.tooLarge(sizeMB: Int(bodyBytes / (1024 * 1024)), kind: kind)
            }
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("events/\(eventID.uuidString)/uploads"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let bodyFile = try writeMultipartBodyFile(
            boundary: boundary,
            fileURL: fileURL,
            fileExtension: fileExtension,
            kind: kind,
            thumbnailData: thumbnailData
        )
        defer { try? FileManager.default.removeItem(at: bodyFile) }

        let responseData: Data
        let response: URLResponse
        do {
            if let onProgress {
                // Upload task + delegate so the UI can show real progress.
                let delegate = UploadProgressDelegate(onProgress: onProgress)
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                (responseData, response) = try await session.upload(for: request, fromFile: bodyFile)
            } else {
                (responseData, response) = try await URLSession.shared.upload(for: request, fromFile: bodyFile)
            }
        } catch let error as URLError {
            throw UploadError.network(error)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw uploadError(response: response, data: responseData)
        }
        return try decoder.decode(MediaItem.self, from: responseData)
    }

    func uploadAvatar(data: Data, fileExtension: String) async throws -> Creator {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/avatar"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = fileOnlyMultipartBody(
            boundary: boundary,
            fieldName: "file",
            filename: "avatar.\(fileExtension.isEmpty ? "jpg" : fileExtension)",
            data: data,
            mimeType: mimeType(for: fileExtension, kind: .photo)
        )

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw uploadError(response: response, data: responseData)
        }
        return try decoder.decode(Creator.self, from: responseData)
    }

    private func uploadError(response: URLResponse, data: Data) -> UploadError {
        let status = (response as? HTTPURLResponse)?.statusCode
        let reason = (try? errorDecoder.decode(ServerError.self, from: data))?.reason
        if status == 413 { return .tooLarge(sizeMB: nil, kind: nil) }
        if status == 401 || status == 403 { return .notAllowed }
        return UploadError.failed(status: status, reason: reason)
    }

    /// Writes the multipart body to a temp file, streaming the media payload
    /// in chunks so only one file-size of disk — not RAM — is used.
    private func writeMultipartBodyFile(
        boundary: String,
        fileURL: URL,
        fileExtension: String,
        kind: MediaKind,
        thumbnailData: Data?
    ) throws -> URL {
        let ext = fileExtension.isEmpty ? defaultFileExtension(for: kind) : fileExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        try handle.write(contentsOf: formField(name: "kind", value: kind.rawValue, boundary: boundary))
        try handle.write(contentsOf: fileFieldHeader(
            name: "file",
            filename: "upload.\(ext)",
            mimeType: mimeType(for: ext, kind: kind),
            boundary: boundary
        ))
        if let input = InputStream(url: fileURL) {
            input.open()
            defer { input.close() }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while input.hasBytesAvailable {
                let read = input.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                try handle.write(contentsOf: Data(buffer[0..<read]))
            }
        }
        try handle.write(contentsOf: Data("\r\n".utf8))
        if let thumbnailData {
            try handle.write(contentsOf: fileField(
                name: "thumbnail",
                filename: "thumbnail.jpg",
                data: thumbnailData,
                mimeType: "image/jpeg",
                boundary: boundary
            ))
        }
        try handle.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
        return tempURL
    }

    private func formField(name: String, value: String, boundary: String) -> Data {
        Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)
    }

    private func fileFieldHeader(name: String, filename: String, mimeType: String, boundary: String) -> Data {
        Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
    }

    private func fileField(name: String, filename: String, data: Data, mimeType: String, boundary: String) -> Data {
        var field = fileFieldHeader(name: name, filename: filename, mimeType: mimeType, boundary: boundary)
        field.append(data)
        field.append(Data("\r\n".utf8))
        return field
    }

    private func fileOnlyMultipartBody(
        boundary: String,
        fieldName: String,
        filename: String,
        data: Data,
        mimeType: String
    ) -> Data {
        var body = Data()
        body.appendFileField(
            name: fieldName,
            filename: filename,
            data: data,
            mimeType: mimeType,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func defaultFileExtension(for kind: MediaKind) -> String {
        kind == .video ? "mp4" : "jpg"
    }

    private func mimeType(for fileExtension: String, kind: MediaKind) -> String {
        UTType(filenameExtension: fileExtension)?.preferredMIMEType
            ?? (kind == .video ? "video/mp4" : "image/jpeg")
    }
}

/// Reports upload body bytes to the caller as a 0–1 fraction.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}

private struct ServerError: Decodable {
    let reason: String?
}

enum UploadError: LocalizedError {
    case tooLarge(sizeMB: Int?, kind: MediaKind?)
    case notAllowed
    case network(URLError)
    case failed(status: Int?, reason: String?)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let sizeMB, let kind):
            let sizeText = sizeMB.map { " (\($0) MB)" } ?? ""
            if kind == .video {
                return "This video is too large to upload\(sizeText) — the limit is 100 MB, about a minute and a half of 1080p. Try a shorter clip or a lower recording resolution."
            }
            return "This file is too large to upload\(sizeText) — the limit is 100 MB."
        case .notAllowed:
            return "You don't have permission to upload to this event."
        case .network(let error):
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection — check your connection and try again."
            case .timedOut:
                return "The upload timed out. Try again on a better connection."
            default:
                return "The upload couldn't reach the server. Please try again."
            }
        case .failed(let status, let reason):
            if let reason { return reason }
            if let status { return "Upload failed with status \(status)." }
            return "Upload failed. Please try again."
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFileField(
        name: String,
        filename: String,
        data: Data,
        mimeType: String,
        boundary: String
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}
