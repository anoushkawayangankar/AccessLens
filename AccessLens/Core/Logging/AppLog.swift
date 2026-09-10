import OSLog

nonisolated enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.accesslens.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    static let vision = Logger(subsystem: subsystem, category: "vision")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
