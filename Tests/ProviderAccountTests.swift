import XCTest
@testable import QuotaPulse

final class ProviderAccountTests: XCTestCase {
    func testAccountsWithSameIDButDifferentProviderAreNotEqual() {
        let id = UUID()
        let miniMax = APIAccount(id: id, name: "Account", provider: .miniMax, apiKey: "key", isEnabled: true)
        let deepSeek = APIAccount(id: id, name: "Account", provider: .deepSeek, apiKey: "key", isEnabled: true)

        XCTAssertNotEqual(miniMax, deepSeek)
    }

    func testUnsupportedUnofficialProvidersAreNotSelectable() {
        XCTAssertFalse(APIProvider.selectableForNewAccounts.contains(.chatGPT))
        XCTAssertFalse(APIProvider.selectableForNewAccounts.contains(.glm))
        XCTAssertTrue(APIProvider.selectableForNewAccounts.contains(.codex))
        XCTAssertFalse(APIProvider.codex.requiresCredential)
        XCTAssertTrue(APIProvider.deepSeek.requiresCredential)
    }
}
