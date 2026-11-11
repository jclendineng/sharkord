import OSLog

// what went wrong out of sight, in the system's log rather than printed: a print is only seen
// with a debugger attached, this shows in Console and in a sysdiagnose from a phone in the
// wild. what failed is public, the error itself stays private as it can name a server
enum Log {
    nonisolated static let network = Logger(subsystem: subsystem, category: "trpc")
    nonisolated static let voice = Logger(subsystem: subsystem, category: "voice")

    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "sharkord"
}
