import Foundation
import Crypto
import NIOCore
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
            do {
                return try await uploadToR2(
                    data: data,
                    key: filename,
                    contentType: file.contentType?.description ?? "application/octet-stream",
                    config: r2,
                    client: req.client
                )
            } catch {
                // Broken R2 credentials/config shouldn't hard-fail uploads —
                // fall back to the local uploads volume.
                req.logger.warning("R2 upload failed, saving locally: \(error.localizedDescription)")
            }
        }

        let destination = URL(fileURLWithPath: config.directory, isDirectory: true)
            .appendingPathComponent(filename)
        try data.write(to: destination)
        return try publicURL(filename: filename, req: req)
    }

    /// Best-effort removal of a previously uploaded object. R2 objects get a
    /// signed DELETE; local files are removed from the uploads directory.
    static func delete(publicURL url: URL, req: Request) async {
        guard let config = req.application.storage[UploadsConfigurationKey.self] else { return }
        if let r2 = config.r2,
           url.absoluteString.hasPrefix(r2.publicBaseURL.absoluteString) {
            try? await deleteFromR2(key: url.lastPathComponent, config: r2, client: req.client)
            return
        }
        // Local mode serves files at /uploads/<filename> — only delete those.
        guard url.path.hasPrefix("/uploads/") else { return }
        let fileURL = URL(fileURLWithPath: config.directory, isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Moves any uploads-directory files referenced by the database into R2 and
    /// rewrites the stored URLs. Idempotent: rows already pointing at R2 (or
    /// anywhere else) are skipped. Runs at boot; never throws so a broken R2
    /// can't take down the app.
    static func migrateLocalUploadsToR2(app: Application) async {
        guard let config = app.storage[UploadsConfigurationKey.self],
              let r2 = config.r2 else { return }
        let logger = app.logger
        let uploadsDir = URL(fileURLWithPath: config.directory, isDirectory: true)
        var cache: [String: URL] = [:]   // filename -> new R2 URL

        func migrateURL(_ raw: String?) async -> String? {
            guard let raw, let url = URL(string: raw),
                  url.path.hasPrefix("/uploads/") else { return nil }
            let filename = url.lastPathComponent
            guard !filename.isEmpty,
                  filename == URL(fileURLWithPath: filename).lastPathComponent else { return nil }
            if let migrated = cache[filename] { return migrated.absoluteString }
            let localFile = uploadsDir.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: localFile) else {
                logger.warning("R2 migration: local file missing for \(raw)")
                return nil
            }
            do {
                let newURL = try await uploadToR2(
                    data: data,
                    key: filename,
                    contentType: contentType(for: filename),
                    config: r2,
                    client: app.client
                )
                cache[filename] = newURL
                try? FileManager.default.removeItem(at: localFile)
                return newURL.absoluteString
            } catch {
                logger.warning("R2 migration: upload failed for \(filename): \(error.localizedDescription)")
                return nil
            }
        }

        var migrated = 0
        do {
            for media in try await MediaModel.query(on: app.db).all() {
                var changed = false
                if let new = await migrateURL(media.url) { media.url = new; changed = true }
                if let new = await migrateURL(media.thumbnailURL) { media.thumbnailURL = new; changed = true }
                if changed { try await media.update(on: app.db); migrated += 1 }
            }
            for creator in try await CreatorModel.query(on: app.db).all() {
                if let new = await migrateURL(creator.avatarURL) {
                    creator.avatarURL = new
                    try await creator.update(on: app.db)
                    migrated += 1
                }
            }
            for event in try await EventModel.query(on: app.db).all() {
                if let new = await migrateURL(event.coverImageURL) {
                    event.coverImageURL = new
                    try await event.update(on: app.db)
                    migrated += 1
                }
            }
        } catch {
            logger.error("R2 migration failed partway: \(error.localizedDescription)")
        }
        if migrated > 0 || !cache.isEmpty {
            logger.info("R2 migration: moved \(cache.count) file(s), updated \(migrated) row(s).")
        }
    }

    private static func contentType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "m4v": return "video/x-m4v"
        default: return "application/octet-stream"
        }
    }

    private static func uploadToR2(data: Data, key: String, contentType: String, config: R2Configuration, client: Client) async throws -> URL {
        var body = ByteBufferAllocator().buffer(capacity: data.count)
        body.writeBytes(data)
        let clientRequest = try r2Request(method: .PUT, key: key, body: body, contentType: contentType, config: config)
        let response = try await client.send(clientRequest)
        guard (200..<300).contains(response.status.code) else {
            let responseBody = response.body.flatMap { buffer in
                var copy = buffer
                return copy.readString(length: copy.readableBytes)
            }?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Abort(.badGateway, reason: "R2 upload failed with status \(response.status.code)\(responseBody.map { ": \($0)" } ?? "").")
        }
        return config.publicBaseURL.appendingPathComponent(key)
    }

    private static func deleteFromR2(key: String, config: R2Configuration, client: Client) async throws {
        let clientRequest = try r2Request(method: .DELETE, key: key, body: ByteBuffer(), contentType: nil, config: config)
        let response = try await client.send(clientRequest)
        guard (200..<300).contains(response.status.code) else {
            throw Abort(.badGateway, reason: "R2 delete failed with status \(response.status.code).")
        }
    }

    private static func r2Request(method: HTTPMethod, key: String, body: ByteBuffer, contentType: String?, config: R2Configuration) throws -> ClientRequest {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let objectURL = config.endpoint
            .appendingPathComponent(config.bucket)
            .appendingPathComponent(encodedKey)
        guard let host = objectURL.host else {
            throw Abort(.internalServerError, reason: "Invalid R2 endpoint.")
        }

        let timestamp = Timestamp()
        let payloadHash = body.readableBytes == 0
            ? "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            : body.getData(at: body.readerIndex, length: body.readableBytes)!.sha256Hex
        let canonicalURI = "/\(config.bucket)/\(encodedKey)"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(timestamp.long)"
        ].joined(separator: "\n")
        let canonicalRequest = [
            method.rawValue,
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

        var headers: HTTPHeaders = [
            "Content-Length": "\(body.readableBytes)",
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": timestamp.long,
            "Authorization": authorization
        ]
        if let contentType {
            headers.add(name: "Content-Type", value: contentType)
        }
        // Object keys are random UUIDs — the bytes at a URL never change, so
        // clients can cache them forever without revalidating.
        if method == .PUT {
            headers.add(name: "Cache-Control", value: "public, max-age=31536000, immutable")
        }
        return ClientRequest(
            method: method,
            url: URI(string: objectURL.absoluteString),
            headers: headers,
            body: body,
            timeout: .seconds(60)
        )
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
        let response = try await req.fileio.asyncStreamFile(at: fileURL.path)
        // UUID filenames are immutable — cache forever.
        response.headers.add(name: .cacheControl, value: "public, max-age=31536000, immutable")
        return response
    }
}
