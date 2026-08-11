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
        XCTAssertNotEqual(
            KeychainStorageIdentity.migrationCompletedKey,
            "keychain.v3.migrationCompleted",
            "The login-Keychain backend must not inherit the Data Protection migration marker"
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

    func testV3QueryUsesLoginKeychainWithoutProvisioningOnlyAttributes() {
        let query = KeychainQueryBuilder.loginKeychainBase(
            service: "test.service",
            account: "test.account"
        )

        XCTAssertNil(query[kSecUseDataProtectionKeychain as String])
        XCTAssertNil(query[kSecAttrAccessible as String])
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
