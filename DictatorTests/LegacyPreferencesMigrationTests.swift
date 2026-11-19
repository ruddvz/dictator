import XCTest
@testable import Dictator

final class LegacyPreferencesMigrationTests: XCTestCase {
    func testMovesPreviousValuesWithoutReplacingNewSettings() {
        let defaults = UserDefaults.standard
        let suffix = UUID().uuidString
        let oldDomain = "dictator.old.\(suffix)"
        let newDomain = "dictator.new.\(suffix)"
        defer {
            defaults.removePersistentDomain(forName: oldDomain)
            defaults.removePersistentDomain(forName: newDomain)
        }
        defaults.setPersistentDomain(["shortcut": "fn", "cleanup": true], forName: oldDomain)
        defaults.setPersistentDomain(["shortcut": "control", "theme": "dark"], forName: newDomain)

        LegacyPreferencesMigration.migrate(defaults: defaults, from: oldDomain, to: newDomain)

        let migrated = defaults.persistentDomain(forName: newDomain) ?? [:]
        XCTAssertEqual(migrated["shortcut"] as? String, "control")
        XCTAssertEqual(migrated["cleanup"] as? Bool, true)
        XCTAssertEqual(migrated["theme"] as? String, "dark")
        XCTAssertEqual(migrated[LegacyPreferencesMigration.migrationMarker] as? Bool, true)
    }

    func testMigrationIsIdempotent() {
        let defaults = UserDefaults.standard
        let suffix = UUID().uuidString
        let oldDomain = "dictator.old.\(suffix)"
        let newDomain = "dictator.new.\(suffix)"
        defer {
            defaults.removePersistentDomain(forName: oldDomain)
            defaults.removePersistentDomain(forName: newDomain)
        }
        defaults.setPersistentDomain(["shortcut": "fn"], forName: oldDomain)
        defaults.setPersistentDomain(["shortcut": "control"], forName: newDomain)

        LegacyPreferencesMigration.migrate(defaults: defaults, from: oldDomain, to: newDomain)
        LegacyPreferencesMigration.migrate(defaults: defaults, from: oldDomain, to: newDomain)

        XCTAssertEqual(defaults.persistentDomain(forName: newDomain)?["shortcut"] as? String, "control")
    }
}
