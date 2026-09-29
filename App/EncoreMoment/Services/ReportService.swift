import Foundation
import EncoreMomentCore

struct ReportService {
    private let baseURL: URL
    private let tokenProvider: () -> String?
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(baseURL: URL = AppConfig.apiBaseURL, tokenProvider: @escaping () -> String? = { TokenHolder.shared.token }) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.encoder = JSONEncoder()
    }

    func submit(_ report: ReportRequest) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("reports"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let token = tokenProvider() else { throw ReportError.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(report)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReportError.failed(status: nil, reason: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let reason = (try? decoder.decode(ServerError.self, from: data))?.reason
            throw ReportError.failed(status: http.statusCode, reason: reason)
        }
    }

    func reports() async throws -> [Report] {
        var request = URLRequest(url: baseURL.appendingPathComponent("reports"))
        request.httpMethod = "GET"
        guard let token = tokenProvider() else { throw ReportError.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReportError.failed(status: nil, reason: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let reason = (try? decoder.decode(ServerError.self, from: data))?.reason
            throw ReportError.failed(status: http.statusCode, reason: reason)
        }
        let reportDecoder = JSONDecoder()
        reportDecoder.dateDecodingStrategy = .iso8601
        return try reportDecoder.decode([Report].self, from: data)
    }

    func deleteReport(id: UUID) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("reports/\(id.uuidString)"))
        request.httpMethod = "DELETE"
        guard let token = tokenProvider() else { throw ReportError.notSignedIn }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReportError.failed(status: nil, reason: nil) }
        guard (200..<300).contains(http.statusCode) else {
            let reason = (try? decoder.decode(ServerError.self, from: data))?.reason
            throw ReportError.failed(status: http.statusCode, reason: reason)
        }
    }
}

private struct ServerError: Decodable {
    let reason: String?
}

enum ReportError: LocalizedError {
    case notSignedIn
    case failed(status: Int?, reason: String?)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to submit reports."
        case .failed(let status, let reason):
            if status == 404 {
                return "Reporting is not enabled on the live backend yet. Deploy the latest backend and try again."
            }
            if let reason { return reason }
            if let status { return "Couldn't submit this report. Server returned status \(status)." }
            return "Couldn't submit this report. Please try again."
        }
    }
}
