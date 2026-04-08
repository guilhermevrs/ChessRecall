import SwiftUI
import DatadogCore
import DatadogCrashReporting
import DatadogLogs
import DatadogTrace
import DatadogRUM
import DatadogSessionReplay
import DatadogProfiling

@main
struct ChessRecallApp: App {
    init() {
        // 1. Core
        Datadog.initialize(
            with: Datadog.Configuration(
                clientToken: "pub02ef95886c4c2d2573c3ff607c8d852b",
                env: "production",
                site: .eu1,
                service: "chess-recall-ios"
            ),
            trackingConsent: .granted
        )

        // 2. Crash + hang detection (must precede RUM)
        CrashReporting.enable()

        // 3. Logs — eager-initialize shared logger before any async work fires
        Logs.enable()
        _ = AppLogger.shared

        // 4. Trace (no first-party hosts; spans available for future internal use)
        Trace.enable()

        // 5. RUM — all features enabled
        RUM.enable(
            with: RUM.Configuration(
                applicationID: "a43c915d-85a6-4a51-b52e-aae7dd2b17f8",
                // UIKit action tracking is recommended by Datadog even for pure SwiftUI apps
                uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
                uiKitActionsPredicate: DefaultUIKitRUMActionsPredicate(),
                // SwiftUI automatic view/action tracking
                swiftUIViewsPredicate: ChessRecallViewsPredicate(),
                swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
                urlSessionTracking: RUM.Configuration.URLSessionTracking(
                    // Track all URLSession calls as RUM resources; no trace header injection
                    // into Lichess (third-party host) since sampleRate is 0
                    firstPartyHostsTracing: .trace(hosts: [], sampleRate: 0),
                    resourceAttributesProvider: { _, response, _, error in
                        var attrs: [String: String] = [:]
                        if let status = (response as? HTTPURLResponse)?.statusCode {
                            attrs["lichess.status_code"] = String(status)
                        }
                        if let error {
                            attrs["lichess.error"] = error.localizedDescription
                        }
                        return attrs.isEmpty ? nil : attrs
                    }
                ),
                trackFrustrations: true,
                trackBackgroundEvents: true,
                longTaskThreshold: 0.1,
                appHangThreshold: 2.0,
                trackWatchdogTerminations: true,
                vitalsUpdateFrequency: .frequent,
                onSessionStart: { sessionId, isDiscarded in
                    AppLogger.shared.info(
                        "rum.session_started",
                        attributes: [
                            "session_id": sessionId,
                            "is_discarded": isDiscarded
                        ]
                    )
                },
                trackAnonymousUser: true,
                trackMemoryWarnings: true,
                trackSlowFrames: true
            )
        )

        // 6. Session Replay — 100% sample rate, mask only sensitive inputs
        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: 100,
                textAndInputPrivacyLevel: .maskSensitiveInputs,
                imagePrivacyLevel: .maskNonBundledOnly,
                touchPrivacyLevel: .show
            )
        )

        // 7. Profiling — correlates with RUM Time-to-Initial-Display (TTID) vital
        // applicationLaunchSampleRate: percentage of app launches that are profiled (0–100).
        // Default is 5; using 100 during early production to capture full signal.
        // Lower this once baseline performance is established.
        Profiling.enable(
            with: Profiling.Configuration(
                applicationLaunchSampleRate: 100
            )
        )

        // 8. Stable anonymous user identity across launches
        let userIdKey = "dd_anonymous_user_id"
        let uid: String
        if let stored = UserDefaults.standard.string(forKey: userIdKey) {
            uid = stored
        } else {
            uid = UUID().uuidString
            UserDefaults.standard.set(uid, forKey: userIdKey)
        }
        Datadog.setUserInfo(
            id: uid,
            extraInfo: [
                "device.locale": Locale.current.identifier,
                "app.version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ]
        )

        // 9. DEBUG mock (unchanged)
        #if DEBUG
        if ProcessInfo.processInfo.environment["MOCK_LICHESS"] == "1" {
            LichessAPIMock.register()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
        }
    }
}
