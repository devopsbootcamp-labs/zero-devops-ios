import XCTest
@testable import ZeroDevOps

final class ZeroDevOpsTests: XCTestCase {

    func testTokenBundleEncoding() throws {
        let bundle = TokenBundle(
            accessToken:  "test.access.token",
            refreshToken: "test.refresh",
            idToken:      nil,
            expiresAt:    Date().addingTimeInterval(3600),
            tenantId:     "tenant-test",
            accountId:    "account-test",
            cloudAccountId: nil
        )
        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(TokenBundle.self, from: data)
        XCTAssertEqual(decoded.accessToken, bundle.accessToken)
        XCTAssertEqual(decoded.tenantId,    bundle.tenantId)
    }

    func testAuthSessionManagerRejectsExpiredToken() {
        let store = TokenStore.shared
        let expired = TokenBundle(
            accessToken:  "expired.token",
            refreshToken: nil,
            idToken:      nil,
            expiresAt:    Date().addingTimeInterval(-60),
            tenantId:     nil,
            accountId:    nil,
            cloudAccountId: nil
        )
        store.save(expired)
        let mgr = AuthSessionManager.shared
        XCTAssertNil(mgr.currentAccessToken(), "Expired token must not be returned")
        store.clear()
    }

    func testAuthSessionManagerAcceptsValidToken() {
        let store = TokenStore.shared
        let valid = TokenBundle(
            accessToken:  "valid.token",
            refreshToken: nil,
            idToken:      nil,
            expiresAt:    Date().addingTimeInterval(3600),
            tenantId:     nil,
            accountId:    nil,
            cloudAccountId: nil
        )
        store.save(valid)
        let mgr = AuthSessionManager.shared
        XCTAssertEqual(mgr.currentAccessToken(), "valid.token")
        store.clear()
    }

    func testJwtClaimsDecoding() {
        // A minimal JWT payload with tenant_id claim
        // Payload: {"sub":"u1","tenant_id":"t-demo","account_id":"a-demo","exp":9999999999}
        let payload = "eyJzdWIiOiJ1MSIsInRlbmFudF9pZCI6InQtZGVtbyIsImFjY291bnRfaWQiOiJhLWRlbW8iLCJleHAiOjk5OTk5OTk5OTl9"
        let fakeJwt = "eyJhbGciOiJSUzI1NiJ9.\(payload).fakesig"
        let claims = OidcAuthManager.decodeJwtClaims(fakeJwt)
        XCTAssertEqual(claims["tenant_id"]  as? String, "t-demo")
        XCTAssertEqual(claims["account_id"] as? String, "a-demo")
    }

    func testCloudAccountResolvedScopeId() {
        let account = CloudAccount(
            id: nil, cloudAccountId: "cld-123", accountId: "acc-456",
            externalAccountId: nil, cloudAccountName: "My AWS", displayName: nil,
            name: nil, provider: "aws", cloudProvider: nil,
            region: "us-east-1", defaultRegion: nil, status: "active", tenantId: nil
        )
        XCTAssertEqual(account.resolvedScopeId, "cld-123")
        XCTAssertEqual(account.resolvedName, "My AWS")
    }
}
