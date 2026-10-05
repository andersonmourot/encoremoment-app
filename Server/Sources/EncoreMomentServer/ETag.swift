import Vapor
import Crypto

/// ETag support for hot read endpoints. The tag is a hash of the final
/// (post-filter) response body, so per-user filtered lists stay correct.
enum ETagResponder {
    /// Encodes `value` with the app's JSON encoder and returns a 200 response
    /// carrying an `ETag`, or a 304 when `If-None-Match` already matches.
    static func respond<T: Encodable>(_ value: T, on req: Request) throws -> Response {
        // Sorted keys keep the body byte-stable across requests — the global
        // encoder emits keys in arbitrary order, which would defeat the tag.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        var headers = HTTPHeaders()
        var body = ByteBuffer()
        try encoder.encode(value, to: &body, headers: &headers)
        let data = Data(buffer: body)
        let etag = "\"\(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())\""

        if req.headers.first(name: "If-None-Match") == etag {
            let response = Response(status: .notModified)
            response.headers.add(name: "ETag", value: etag)
            return response
        }
        let response = Response(status: .ok, body: .init(buffer: body))
        response.headers.contentType = HTTPMediaType.json
        response.headers.add(name: "ETag", value: etag)
        return response
    }
}
