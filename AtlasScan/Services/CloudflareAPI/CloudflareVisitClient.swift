import Foundation

// MARK: - CloudflareVisitClient
//
// Stub API client for fetching and creating visits from the Cloudflare D1 database.
//
// Design:
//   - Offline-first: the app always works from local persistence; this client
//     enriches the visit list with server-side records when connectivity allows.
//   - The response types mirror the AtlasContracts AppointmentV1 shape so that
//     the `appointmentId` value flows directly into CaptureSessionDraft.
//   - Replace the stub implementations with real URLSession calls once the
//     Cloudflare Workers API endpoint is available.
//
// NOT YET WIRED — transport stubs only.

// MARK: - RemoteVisit

/// A visit record fetched from the Cloudflare D1 database.
/// Mirrors AppointmentV1 from Atlas-contracts.
struct RemoteVisit: Identifiable, Codable {
    /// Unique appointment / visit identifier (UUID string).
    let id: String
    /// Human-readable job reference.
    let visitReference: String
    /// Property street address.
    let propertyAddress: String?
    /// ISO-8601 scheduled start time.
    let scheduledAt: String?
    /// Current lifecycle status string.
    let status: String
    /// Assigned engineer name.
    let engineerName: String?

    enum CodingKeys: String, CodingKey {
        case id              = "appointment_id"
        case visitReference  = "visit_reference"
        case propertyAddress = "property_address"
        case scheduledAt     = "scheduled_at"
        case status
        case engineerName    = "engineer_name"
    }
}

// MARK: - CloudflareVisitClientError

enum CloudflareVisitClientError: LocalizedError {
    case notConfigured
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:         return "Cloudflare API is not configured."
        case .networkError(let e):   return "Network error: \(e.localizedDescription)"
        case .decodingError(let e):  return "Response decoding failed: \(e.localizedDescription)"
        case .serverError(let code): return "Server returned HTTP \(code)."
        }
    }
}

// MARK: - CloudflareVisitClient

/// Fetches and creates visit records via the Atlas Cloudflare Workers API.
///
/// Usage:
///   1. Configure `baseURL` with the Workers endpoint.
///   2. Call `fetchUpcomingVisits()` to list scheduled appointments.
///   3. Call `createVisit(draft:)` to push a new draft to the database.
///
/// All methods are async and throw ``CloudflareVisitClientError``.
@MainActor
final class CloudflareVisitClient: ObservableObject {

    // MARK: Shared singleton

    static let shared = CloudflareVisitClient()

    // MARK: Configuration

    /// Base URL of the Cloudflare Workers API.  Nil means remote sync is disabled.
    var baseURL: URL? = nil

    private var isConfigured: Bool { baseURL != nil }

    private let session: URLSession

    // MARK: Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API (stubs)

    /// Fetches upcoming / scheduled visits for the current engineer from Cloudflare D1.
    ///
    /// STUB — returns synthetic fixture data simulating a network response.
    /// Replace with a real URLSession data task when the API is available.
    func fetchUpcomingVisits() async throws -> [RemoteVisit] {
        guard isConfigured else {
            // Return empty list gracefully when API is not yet configured.
            return []
        }

        // Transport stub — simulate a network round trip.
        try await Task.sleep(nanoseconds: 300_000_000)  // 0.3 s

        // Placeholder: return fixture visits.
        return stubFixtureVisits()
    }

    /// Creates a new visit record in Cloudflare D1, derived from a local capture draft.
    /// Returns the remote visit ID on success.
    ///
    /// STUB — simulates the creation and returns a synthetic ID.
    func createVisit(reference: String, propertyAddress: String?) async throws -> String {
        guard isConfigured else {
            // Gracefully return a local UUID when the API is not configured.
            return UUID().uuidString
        }

        // Transport stub — simulate a round trip.
        try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 s

        return "remote_\(UUID().uuidString)"
    }

    // MARK: - Private: fixture data

    private func stubFixtureVisits() -> [RemoteVisit] {
        [
            RemoteVisit(
                id: "APT-2025-001",
                visitReference: "JOB-2025-0601",
                propertyAddress: "12 Coronation Street, Manchester, M1 1AA",
                scheduledAt: "2025-06-01T09:00:00Z",
                status: "scheduled",
                engineerName: nil
            ),
            RemoteVisit(
                id: "APT-2025-002",
                visitReference: "JOB-2025-0602",
                propertyAddress: "47 Baker Street, London, W1U 7AJ",
                scheduledAt: "2025-06-01T14:00:00Z",
                status: "confirmed",
                engineerName: nil
            )
        ]
    }
}
