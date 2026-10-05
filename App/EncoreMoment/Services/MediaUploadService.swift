import Foundation
import UniformTypeIdentifiers
import EncoreMomentCore

struct MediaUploadService {
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

    func upload(
        data: Data,
        fileExtension: String,
        kind: MediaKind,
        to eventID: UUID,
        thumbnailData: Data? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> MediaItem {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("events/\(eventID.uuidString)/uploads"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body = multipartBody(
            boundary: boundary,
            data: data,
            fileExtension: fileExtension,
            kind: kind,
            thumbnailData: thumbnailData
        )

        let responseData: Data
        let response: URLResponse
        if let onProgress {
            // Upload task + delegate so the UI can show real progress.
            let delegate = UploadProgressDelegate(onProgress: onProgress)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            (responseData, response) = try await session.upload(for: request, from: body)
        } else {
            (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
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
        return UploadError.failed(status: status, reason: reason)
    }

    private func multipartBody(
        boundary: String,
        data: Data,
        fileExtension: String,
        kind: MediaKind,
        thumbnailData: Data?
    ) -> Data {
        var body = Data()
        let ext = fileExtension.isEmpty ? defaultFileExtension(for: kind) : fileExtension

        body.appendFormField(name: "kind", value: kind.rawValue, boundary: boundary)
        body.appendFileField(
            name: "file",
            filename: "upload.\(ext)",
            data: data,
            mimeType: mimeType(for: ext, kind: kind),
            boundary: boundary
        )
        if let thumbnailData {
            body.appendFileField(
                name: "thumbnail",
                filename: "thumbnail.jpg",
                data: thumbnailData,
                mimeType: "image/jpeg",
                boundary: boundary
            )
        }
        body.append("--\(boundary)--\r\n")
        return body
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
    case failed(status: Int?, reason: String?)

    var errorDescription: String? {
        switch self {
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
