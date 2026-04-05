import Foundation

// MARK: - ExportDraftState

/// Tracks the state of the export pipeline for a scan job.
struct ExportDraftState: Codable {

    var jobID: UUID

    var status: ExportStatus

    /// ISO-8601 timestamp of last export attempt
    var lastAttemptedAt: Date?

    /// ISO-8601 timestamp of last successful export
    var lastSucceededAt: Date?

    /// Validation issues detected before the last export attempt
    var validationIssues: [ValidationIssue]

    /// Serialised bundle payload (JSON), stored temporarily before share/upload
    var bundlePayloadJSON: String?

    init(jobID: UUID) {
        self.jobID = jobID
        self.status = .notStarted
        self.validationIssues = []
    }

    var hasBlockingIssues: Bool {
        validationIssues.contains(where: { $0.severity == .blocking })
    }
}

// MARK: - ExportStatus

enum ExportStatus: String, Codable {
    case notStarted     = "not_started"
    case validating     = "validating"
    case readyToExport  = "ready_to_export"
    case exporting      = "exporting"
    case exported       = "exported"
    case failed         = "failed"

    var displayName: String {
        switch self {
        case .notStarted:     return "Not Started"
        case .validating:     return "Validating"
        case .readyToExport:  return "Ready to Export"
        case .exporting:      return "Exporting…"
        case .exported:       return "Exported"
        case .failed:         return "Failed"
        }
    }
}

// MARK: - ValidationIssue

struct ValidationIssue: Identifiable, Codable {
    var id: UUID = UUID()
    var severity: IssueSeverity
    var message: String
    var roomID: UUID?
    var objectID: UUID?

    enum IssueSeverity: String, Codable {
        case blocking = "blocking"
        case warning  = "warning"
        case info     = "info"
    }
}
