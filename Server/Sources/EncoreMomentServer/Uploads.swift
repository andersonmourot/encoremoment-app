import Foundation
import Crypto
import EncoreMomentCore
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

struct PresignedUpload {
    /// PUT URL signed for direct client→R2 upload (15-minute TTL).
    let uploadURL: URL
    /// `staging/<uuid>.<ext>` — quarantined until registration promotes it.
    let key: String
}

enum UploadStorage {
    /// Signs a PUT for a staging key. Staging objects sit outside the promoted
    /// media namespace until `promoteStaged` verifies and copies them.
    static func presignedPut(contentType: String, fileExtension ext: String, config: R2Configuration) throws -> PresignedUpload {
        let key = "staging/\(UUID().uuidString).\(ext)"
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let objectURL = config.endpoint
            .appendingPathComponent(config.bucket)
            .appendingPathComponent(encodedKey)
        guard let host = objectURL.host else {
            throw Abort(.internalServerError, reason: "Invalid R2 endpoint.")
        }

        let timestamp = Timestamp()
        let credentialScope = "\(timestamp.short)/auto/s3/aws4_request"
        let signedHeaders = "content-type;host"
        let queryItems: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", "\(config.accessKeyID)/\(credentialScope)"),
            ("X-Amz-Date", timestamp.long),
            ("X-Amz-Expires", "900"),
            ("X-Amz-SignedHeaders", signedHeaders),
        ]
        let canonicalQuery = queryItems
            .map { "\($0.0.awsSigV4Encoded)=\($0.1.awsSigV4Encoded)" }
            .sorted()
            .joined(separator: "&")
        let canonicalRequest = [
            "PUT",
            "/\(config.bucket)/\(encodedKey)",
            canonicalQuery,
            "content-type:\(contentType)\nhost:\(host)\n",
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            timestamp.long,
            credentialScope,
            canonicalRequest.sha256Hex
        ].joined(separator: "\n")
        let signature = signingKey(secret: config.secretAccessKey, date: timestamp.short)
            .hmacHex(stringToSign)

        guard var components = URLComponents(url: objectURL, resolvingAgainstBaseURL: false) else {
            throw Abort(.internalServerError, reason: "Invalid R2 endpoint.")
        }
        components.percentEncodedQuery = canonicalQuery + "&X-Amz-Signature=\(signature)"
        guard let uploadURL = components.url else {
            throw Abort(.internalServerError, reason: "Invalid R2 endpoint.")
        }
        return PresignedUpload(uploadURL: uploadURL, key: key)
    }

    /// Validates a staged object (existence + magic bytes match the claimed
    /// kind), copies it to the flat media namespace, and removes the staging
    /// object. Returns the public URL of the promoted object.
    static func promoteStaged(key: String, kind: MediaKind, config: R2Configuration, client: Client) async throws -> URL {
        let parts = key.split(separator: "/")
        guard parts.count == 2, parts[0] == "staging",
              !parts[1].contains(".."), parts[1].count > 4 else {
            throw Abort(.badRequest, reason: "Invalid upload key.")
        }
        let finalKey = String(parts[1])

        let exists: Bool = try await {
            let request = try r2Request(method: .HEAD, key: key, body: ByteBuffer(), contentType: nil, config: config)
            let response = try await client.send(request)
            return response.status.code == 200
        }()
        guard exists else {
            throw Abort(.badRequest, reason: "Uploaded file was not received. Try uploading again.")
        }

        let prefix = try await fetchPrefix(key: key, config: config, client: client)
        guard MagicBytes.matches(prefix, kind: kind) else {
            try? await deleteFromR2(key: key, config: config, client: client)
            throw Abort(.badRequest, reason: "The uploaded file doesn't look like valid \(kind == .video ? "video" : "image") data.")
        }

        let copyRequest = try r2Request(
            method: .PUT,
            key: finalKey,
            body: ByteBuffer(),
            contentType: contentType(for: finalKey),
            config: config,
            extraSignedHeaders: [
                ("x-amz-copy-source", "/\(config.bucket)/\(key)"),
                ("x-amz-metadata-directive", "REPLACE"),
            ]
        )
        let copyResponse = try await client.send(copyRequest)
        guard (200..<300).contains(copyResponse.status.code) else {
            throw Abort(.badGateway, reason: "Finalizing the upload failed. Please try again.")
        }
        try? await deleteFromR2(key: key, config: config, client: client)
        return config.publicBaseURL.appendingPathComponent(finalKey)
    }

    /// Removes a staging object directly by key (upload abandoned/rejected).
    static func deleteStaged(key: String, config: R2Configuration, client: Client) async {
        try? await deleteFromR2(key: key, config: config, client: client)
    }

    /// Fetches the first 64 bytes of an object for magic-byte validation —
    /// enough for JPEG/PNG/GIF/WEBP/ISO-BMFF(ftyp) signatures without pulling
    /// the whole file.
    private static func fetchPrefix(key: String, config: R2Configuration, client: Client) async throws -> Data {
        let request = try r2Request(
            method: .GET, key: key, body: ByteBuffer(), contentType: nil, config: config,
            extraSignedHeaders: [("range", "bytes=0-63")]
        )
        let response = try await client.send(request)
        guard (200..<300).contains(response.status.code) else {
            throw Abort(.badGateway, reason: "Could not verify the uploaded file.")
        }
        guard var body = response.body else {
            throw Abort(.badGateway, reason: "Could not verify the uploaded file.")
        }
        return body.readData(length: min(64, body.readableBytes)) ?? Data()
    }

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

    private static func r2Request(
        method: HTTPMethod,
        key: String,
        body: ByteBuffer,
        contentType: String?,
        config: R2Configuration,
        extraSignedHeaders: [(String, String)] = []
    ) throws -> ClientRequest {
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
        // Headers included here are signed and must be sent verbatim.
        var headerPairs: [(String, String)] = [
            ("host", host),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", timestamp.long),
        ]
        headerPairs.append(contentsOf: extraSignedHeaders.map {
            ($0.0.lowercased(), $0.1.trimmingCharacters(in: .whitespaces))
        })
        headerPairs.sort { $0.0 < $1.0 }
        let signedHeaders = headerPairs.map(\.0).joined(separator: ";")
        let canonicalHeaders = headerPairs.map { "\($0.0):\($0.1)" }.joined(separator: "\n")
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
        for (name, value) in extraSignedHeaders {
            headers.add(name: name, value: value)
        }
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

    /// RFC 3986 strict encoding for SigV4 query params — `urlQueryAllowed`
    /// leaves `+`, `/`, `=` unencoded and produces bad signatures.
    var awsSigV4Encoded: String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: unreserved) ?? self
    }
}

/// File-signature check for staged uploads — magic bytes can't be spoofed by
/// renaming a file, so this blocks `.exe`-as-`.mp4` uploads.
enum MagicBytes {
    static func matches(_ data: Data, kind: MediaKind) -> Bool {
        guard data.count >= 12 else { return false }
        switch kind {
        case .photo:
            return data.starts(with: [0xFF, 0xD8, 0xFF])          // JPEG
                || data.starts(with: [0x89, 0x50, 0x4E, 0x47])    // PNG
                || data.starts(with: [0x47, 0x49, 0x46, 0x38])    // GIF8
                || isWebP(data)
                || hasFtypBox(data)                               // HEIC/AVIF
        case .video:
            return hasFtypBox(data)                               // MP4/MOV/M4V (ISO-BMFF)
        }
    }

    /// ISO-BMFF files carry a `ftyp` box at bytes 4–7.
    private static func hasFtypBox(_ data: Data) -> Bool {
        data[data.index(data.startIndex, offsetBy: 4)...]
            .starts(with: [0x66, 0x74, 0x79, 0x70])
    }

    private static func isWebP(_ data: Data) -> Bool {
        data.starts(with: [0x52, 0x49, 0x46, 0x46])               // RIFF
            && data[data.index(data.startIndex, offsetBy: 8)...]
                .starts(with: [0x57, 0x45, 0x42, 0x50])           // WEBP
    }
}

/// Per-user rate limit on upload-signing so a scripted account can't mint
/// unbounded staging objects. One media upload costs two signs (file + thumb).
actor SignRateLimiter {
    private var hits: [UUID: [Date]] = [:]

    func allow(user: UUID, maxPerHour: Int = 120) -> Bool {
        let now = Date()
        var recent = (hits[user] ?? []).filter { now.timeIntervalSince($0) < 3600 }
        guard recent.count < maxPerHour else {
            hits[user] = recent
            return false
        }
        recent.append(now)
        hits[user] = recent
        return true
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

private struct SignUploadRequest: Content {
    let contentType: String
    let fileExtension: String
}

struct SignUploadResponse: Content {
    let uploadURL: URL
    let key: String
}

struct UploadController: RouteCollection {
    let signRateLimiter = SignRateLimiter()

    /// Content types a client may ask to upload directly. The value is baked
    /// into the presigned URL, so the PUT must send it verbatim — the stored
    /// object always carries a media MIME type, never e.g. text/html.
    private static let allowedContentTypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/gif",
        "video/mp4", "video/quicktime", "video/x-m4v",
    ]

    private static let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "heic", "gif", "mp4", "mov", "m4v",
    ]

    func boot(routes: RoutesBuilder) throws {
        routes.get("uploads", ":filename", use: show)
        routes
            .grouped(UserToken.authenticator())
            .grouped(UserToken.guardMiddleware())
            .post("uploads", "sign", use: sign)
    }

    /// Issues a presigned PUT URL for direct client→R2 upload into the
    /// quarantined `staging/` prefix. Registration (`POST /events/:id/uploads/
    /// complete`) is what validates and promotes the object to a public URL.
    func sign(req: Request) async throws -> SignUploadResponse {
        let token = try req.auth.require(UserToken.self)
        guard let config = req.application.storage[UploadsConfigurationKey.self],
              let r2 = config.r2 else {
            throw Abort(.notImplemented, reason: "Direct uploads are not configured.")
        }
        let body = try req.content.decode(SignUploadRequest.self)
        let ext = body.fileExtension.lowercased()
        guard Self.allowedExtensions.contains(ext),
              Self.allowedContentTypes.contains(body.contentType.lowercased()) else {
            throw Abort(.badRequest, reason: "Unsupported file type.")
        }
        guard await signRateLimiter.allow(user: try token.requireUserID()) else {
            throw Abort(.tooManyRequests, reason: "Too many uploads. Try again later.")
        }
        let presigned = try UploadStorage.presignedPut(
            contentType: body.contentType,
            fileExtension: ext,
            config: r2
        )
        return SignUploadResponse(uploadURL: presigned.uploadURL, key: presigned.key)
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
