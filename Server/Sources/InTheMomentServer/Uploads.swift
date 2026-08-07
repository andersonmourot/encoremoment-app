import Foundation
import Crypto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

struct UploadsConfiguration {
    let directory: String
    let r2: R2Configuration?
}

struct R2Configuration {
    let bucket: String
    let endpoint: URL
    let accessKeyID: String
    let secretAccessKey: String
    let publicBaseURL: URL

    static func fromEnvironment() -> R2Configuration? {
        guard let bucket = Environment.get("R2_BUCKET"),
              let endpointRaw = Environment.get("R2_ENDPOINT"),
              let endpoint = URL(string: endpointRaw),
              let accessKeyID = Environment.get("R2_ACCESS_KEY_ID"),
              let secretAccessKey = Environment.get("R2_SECRET_ACCESS_KEY"),
              let publicBaseRaw = Environment.get("R2_PUBLIC_BASE_URL"),
              let publicBaseURL = URL(string: publicBaseRaw) else {
            return nil
        }
        return R2Configuration(
            bucket: bucket,
            endpoint: endpoint,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            publicBaseURL: publicBaseURL
        )
    }
}

struct UploadsConfigurationKey: StorageKey {
    typealias Value = UploadsConfiguration
}

enum UploadStorage {
    static func save(_ file: File, fallbackExtension: String, req: Request) async throws -> URL {
        guard let config = req.application.storage[UploadsConfigurationKey.self] else {
            throw Abort(.internalServerError, reason: "Uploads are not configured.")
        }
        let ext = fileExtension(for: file.filename, fallbackExtension: fallbackExtension)
        let filename = "\(UUID().uuidString).\(ext)"

        var buffer = file.data
        guard let data = buffer.readData(length: buffer.readableBytes), !data.isEmpty else {
            throw Abort(.badRequest, reason: "Upload file is empty.")
        }

        if let r2 = config.r2 {
            return try await uploadToR2(
                data: data,
                key: filename,
                contentType: file.contentType?.description ?? "application/octet-stream",
                config: r2
            )
        }

        let destination = URL(fileURLWithPath: config.directory, isDirectory: true)
            .appendingPathComponent(filename)
        try data.write(to: destination)
        return try publicURL(filename: filename, req: req)
    }

    private static func uploadToR2(data: Data, key: String, contentType: String, config: R2Configuration) async throws -> URL {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let objectURL = config.endpoint
            .appendingPathComponent(config.bucket)
            .appendingPathComponent(encodedKey)
        guard let host = objectURL.host else {
            throw Abort(.internalServerError, reason: "Invalid R2 endpoint.")
        }

        let timestamp = Timestamp()
        let payloadHash = data.sha256Hex
        let canonicalURI = "/\(config.bucket)/\(encodedKey)"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(timestamp.long)"
        ].joined(separator: "\n")
        let canonicalRequest = [
            "PUT",
            canonicalURI,
            "",
            canonicalHeaders,
            "",
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        let credentialScope = "\(timestamp.short)/auto/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            timestamp.long,
            credentialScope,
            canonicalRequest.sha256Hex
        ].joined(separator: "\n")
        let signature = signingKey(secret: config.secretAccessKey, date: timestamp.short)
            .hmacHex(stringToSign)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: objectURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(timestamp.long, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Abort(.badGateway, reason: "R2 upload failed with status \(status)\(body.map { ": \($0)" } ?? "").")
        }
        return config.publicBaseURL.appendingPathComponent(key)
    }

    static func publicURL(filename: String, req: Request) throws -> URL {
        if let base = Environment.get("PUBLIC_BASE_URL"),
           let url = URL(string: base)?.appendingPathComponent("uploads").appendingPathComponent(filename) {
            return url
        }
        guard let host = req.headers.first(name: "Host") else {
            throw Abort(.internalServerError, reason: "Could not build upload URL.")
        }
        let proto = req.headers.first(name: "X-Forwarded-Proto") ?? publicScheme(for: host)
        guard let url = URL(string: "\(proto)://\(host)/uploads/\(filename)") else {
            throw Abort(.internalServerError, reason: "Could not build upload URL.")
        }
        return url
    }

    private static func publicScheme(for host: String) -> String {
        if host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1") || host.hasPrefix("0.0.0.0") {
            return "http"
        }
        return "https"
    }

    private static func fileExtension(for filename: String, fallbackExtension: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let allowed = Set(["jpg", "jpeg", "png", "heic", "webp", "gif", "mp4", "mov", "m4v"])
        if allowed.contains(ext) { return ext }
        return fallbackExtension
    }

    private static func signingKey(secret: String, date: String) -> Data {
        let kDate = Data("AWS4\(secret)".utf8).hmac(date)
        let kRegion = kDate.hmac("auto")
        let kService = kRegion.hmac("s3")
        return kService.hmac("aws4_request")
    }
}

private struct Timestamp {
    let short: String
    let long: String

    init(date: Date = Date()) {
        let shortFormatter = DateFormatter()
        shortFormatter.calendar = Calendar(identifier: .gregorian)
        shortFormatter.locale = Locale(identifier: "en_US_POSIX")
        shortFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        shortFormatter.dateFormat = "yyyyMMdd"
        short = shortFormatter.string(from: date)

        let longFormatter = DateFormatter()
        longFormatter.calendar = Calendar(identifier: .gregorian)
        longFormatter.locale = Locale(identifier: "en_US_POSIX")
        longFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        longFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        long = longFormatter.string(from: date)
    }
}

private extension String {
    var sha256Hex: String {
        Data(utf8).sha256Hex
    }
}

private extension Data {
    var sha256Hex: String {
        Data(SHA256.hash(data: self)).hexString
    }

    func hmac(_ string: String) -> Data {
        hmac(Data(string.utf8))
    }

    func hmac(_ data: Data) -> Data {
        let key = SymmetricKey(data: self)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    func hmacHex(_ string: String) -> String {
        hmac(string).hexString
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

struct UploadController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("uploads", ":filename", use: show)
    }

    func show(req: Request) async throws -> Response {
        guard let filename = req.parameters.get("filename"),
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              let config = req.application.storage[UploadsConfigurationKey.self] else {
            throw Abort(.notFound)
        }

        let fileURL = URL(fileURLWithPath: config.directory, isDirectory: true)
            .appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw Abort(.notFound)
        }
        return try await req.fileio.asyncStreamFile(at: fileURL.path)
    }
}
