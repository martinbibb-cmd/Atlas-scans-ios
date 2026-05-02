import UIKit

// MARK: - TestFlightFeedbackReporter
//
// Assembles a pre-filled feedback report for TestFlight issue submissions.
//
// The report includes app version, build number, device model, and iOS version
// so testers can share all relevant context in one tap via the system share sheet.
//
// Usage:
//   ShareSheet(items: TestFlightFeedbackReporter.makeShareItems())

enum TestFlightFeedbackReporter {

    /// Returns share-sheet items for a TestFlight issue report.
    ///
    /// The returned array contains a pre-filled text string that includes
    /// build info, device info, and a blank issue template.
    /// Pass this directly to ``ShareSheet``.
    static func makeShareItems() -> [Any] {
        [reportText]
    }

    // MARK: - Report body

    private static var reportText: String {
        """
        ## Atlas Scan — TestFlight Issue Report

        **App Version**: \(appVersion)
        **Build Number**: \(buildNumber)
        **Device Model**: \(deviceModel)
        **iOS Version**: \(iosVersion)

        ---

        ### What happened

        <Describe what you tapped / did, step by step.>

        ### Expected behaviour

        <What should have happened.>

        ### Actual behaviour

        <What actually happened — crash, blank screen, wrong data, etc.>

        ### Atlas Mind handoff status

        <On the Visit Complete screen: "Atlas Mind URL: Ready" or "Atlas Mind URL: Not available">

        ### Screenshots / crash log

        <Attach screenshots or Xcode crash log here.>

        ---
        Reported via Atlas Scan \(appVersion) (build \(buildNumber)) on \(deviceModel) running iOS \(iosVersion).
        """
    }

    // MARK: - Data sources

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    private static var deviceModel: String {
        var sysInfo = utsname()
        uname(&sysInfo)
        let mirror = Mirror(reflecting: sysInfo.machine)
        let identifier = mirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8(bitPattern: $0))) }
        return String(identifier)
    }

    private static var iosVersion: String {
        UIDevice.current.systemVersion
    }
}
