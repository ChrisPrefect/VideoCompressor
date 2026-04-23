import Foundation
import Observation

/// Hält die Session-Statistik im Speicher und publiziert Änderungen, damit
/// der Library-Header live aktualisiert.
@MainActor
@Observable
public final class SessionStatisticsService {
    private enum Keys {
        static let lifetimeStatistics = "statistics.lifetime.v1"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    public private(set) var statistics: SessionStatistics = .empty
    public private(set) var lifetimeStatistics: SessionStatistics

    public init(defaults: UserDefaults = AppGroup.sharedDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.lifetimeStatistics),
           let parsed = try? decoder.decode(SessionStatistics.self, from: data) {
            self.lifetimeStatistics = parsed
        } else {
            self.lifetimeStatistics = .empty
        }
    }

    public func record(_ result: ExportResult) {
        statistics.record(result)
        lifetimeStatistics.record(result)
        persistLifetimeStatistics()
    }

    public func reset() {
        statistics = .empty
    }

    private func persistLifetimeStatistics() {
        guard let data = try? encoder.encode(lifetimeStatistics) else { return }
        defaults.set(data, forKey: Keys.lifetimeStatistics)
    }
}
