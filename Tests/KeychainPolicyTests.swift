import Security
import XCTest
@testable import QuotaPulse

final class KeychainPolicyTests: XCTestCase {
    func testLegacyReadOnlyOccursWhenV3ItemIsAbsentAndMigrationIsIncomplete() {
        XCTAssertTrue(
            KeychainMigrationPolicy.shouldReadLegacy(
                v3Status: errSecItemNotFound,
                migrationCompleted: false
            )
        )
        XCTAssertFalse(
            KeychainMigrationPolicy.shouldReadLegacy(
                v3Status: errSecItemNotFound,
                migrationCompleted: true
            )
        )
    }

    func testAuthorizationFailuresNeverTriggerLegacyRead() {
        XCTAssertFalse(
            KeychainMigrationPolicy.shouldReadLegacy(
                v3Status: errSecAuthFailed,
                migrationCompleted: false
            )
        )
        XCTAssertFalse(
            KeychainMigrationPolicy.shouldReadLegacy(
                v3Status: errSecInteractionNotAllowed,
                migrationCompleted: false
            )
        )
    }

    func testV3QueryOptsIntoDataProtectionKeychain() {
        let query = KeychainQueryBuilder.dataProtectionBase(
            service: "test.service",
            account: "test.account"
        )

        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "test.service")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "test.account")
    }

    func testUnchangedKeyringDoesNotRequireAWrite() {
        let accountID = UUID()
        let keys = [accountID: "secret"]

        XCTAssertFalse(KeyringPersistencePolicy.requiresWrite(current: keys, target: keys))
        XCTAssertTrue(
            KeyringPersistencePolicy.requiresWrite(
                current: keys,
                target: [accountID: "changed"]
            )
        )
        XCTAssertTrue(KeyringPersistencePolicy.requiresWrite(current: keys, target: [:]))
    }

    func testHostedTestDetectionHasMultipleIndependentSignals() {
        XCTAssertTrue(
            RuntimeEnvironment.detectsUnitTests(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
                arguments: [],
                hasXCTestClass: false
            )
        )
        XCTAssertTrue(
            RuntimeEnvironment.detectsUnitTests(
                environment: [:],
                arguments: ["QuotaPulse", "-XCTest"],
                hasXCTestClass: false
            )
        )
        XCTAssertFalse(
            RuntimeEnvironment.detectsUnitTests(
                environment: [:],
                arguments: ["QuotaPulse"],
                hasXCTestClass: false
            )
        )
    }
}
