import Foundation

enum LegacyPreferencesMigration {
    static let previousBundleIdentifier = "com.ruddvz.hushkey"
    static let migrationMarker = "dictator.didMigrateHushKeyPreferences"

    static func migrateForCurrentApp() {
        guard !AppDataDirectory.isRunningTests,
              let currentBundleIdentifier = Bundle.main.bundleIdentifier else { return }
        migrate(defaults: .standard, from: previousBundleIdentifier, to: currentBundleIdentifier)
    }

    static func migrate(defaults: UserDefaults, from oldDomain: String, to newDomain: String) {
        guard oldDomain != newDomain else { return }
        var currentValues = defaults.persistentDomain(forName: newDomain) ?? [:]
        guard currentValues[migrationMarker] as? Bool != true else { return }
        let previousValues = defaults.persistentDomain(forName: oldDomain) ?? [:]
        guard !previousValues.isEmpty else { return }

        for (key, value) in previousValues where currentValues[key] == nil {
            currentValues[key] = value
        }
        currentValues[migrationMarker] = true
        defaults.setPersistentDomain(currentValues, forName: newDomain)
    }
}
