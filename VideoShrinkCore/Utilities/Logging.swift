import Foundation
import os

/// Dünner Wrapper um `os.Logger` mit fertigen Subsystemen, damit alle
/// Module einheitlich loggen. Nonisolated, damit Background-Code aus
/// Services/Actors loggen kann.
nonisolated public enum Log {
    private static let subsystem = "iteconomy.ch.VideoCompressor"

    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let analysis = Logger(subsystem: subsystem, category: "analysis")
    public static let transcoding = Logger(subsystem: subsystem, category: "transcoding")
    public static let presets = Logger(subsystem: subsystem, category: "presets")
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let share = Logger(subsystem: subsystem, category: "share")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
