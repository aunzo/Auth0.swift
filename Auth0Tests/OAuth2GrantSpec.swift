import Quick
import Nimble
import Foundation

@testable import Auth0

class OAuth2GrantSpec: QuickSpec {

    override class func spec() {

        let domain = URL.httpsURL(from: "samples.auth0.com")
        let authentication = Auth0Authentication(clientId: "CLIENT_ID", url: domain)
        let idToken = generateJWT(iss: "\(domain.absoluteString)/", aud: [authentication.clientId]).string
        let nonce = "a1b2c3d4e5"
        let issuer = "\(domain.absoluteString)/"
        let leeway = 60 * 1000

        beforeEach {
            URLProtocol.registerClass(StubURLProtocol.self)
        }

        afterEach {
            NetworkStub.clearStubs()
            URLProtocol.unregisterClass(StubURLProtocol.self)
        }

        describe("Authorization Code w/PKCE") {

            let method = "S256"
            let redirectURL = URL(string: "https://samples.auth0.com/callback")!
            var verifier: String!
            var challenge: String!
            var pkce: PKCE!

            beforeEach {
                verifier = "\(arc4random())"
                challenge = "\(arc4random())"
                pkce = PKCE(authentication: authentication, redirectURL: redirectURL, verifier: verifier, challenge: challenge, method: method, issuer: issuer, leeway: leeway, nonce: nil)
            }


            it("shoud build credentials") {
                let token = UUID().uuidString
                let code = UUID().uuidString
                let values = ["code": code]
                NetworkStub.addStub(condition: {
                    $0.isToken(domain.host!) && $0.hasAtLeast(["code": code, "code_verifier": pkce.verifier, "grant_type": "authorization_code", "redirect_uri": pkce.redirectURL.absoluteString])
                }, response: authResponse(accessToken: token, idToken: idToken))
                NetworkStub.addStub(condition: {
                    $0.isJWKSPath(domain.host!)
                }, response: jwksResponse())
                waitUntil { done in
                    pkce.credentials(from: values) {
                        expect($0).to(haveCredentials(token, idToken))
                        done()
                    }
                }
            }

            it("shoud report error to get credentials") {
                waitUntil { done in
                    pkce.credentials(from: [:]) {
                        expect($0).to(beUnsuccessful())
                        done()
                    }
                }
            }

            it("should specify pkce parameters") {
                expect(pkce.defaults["code_challenge_method"]) == "S256"
                expect(pkce.defaults["code_challenge"]) == challenge
            }

            it("should get values from generator") {
                let generator = ChallengeGenerator()
                let authentication = Auth0Authentication(clientId: "CLIENT_ID", url: domain)
                pkce = PKCE(authentication: authentication, generator: generator, redirectURL: redirectURL, issuer: issuer, leeway: leeway, nonce: nil)
                
                expect(pkce.defaults["code_challenge_method"]) == generator.method
                expect(pkce.defaults["code_challenge"]) == generator.challenge
                expect(pkce.verifier) == generator.verifier
            }

            it("should extract query parameters from url components") {
                let url = URL(string: "https://samples.auth0.com/callback?foo=bar&baz=qux")!
                let values = ["foo": "bar", "baz": "qux"]
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                expect(pkce.values(fromComponents: components)) == values
            }

        }

        describe("Authorization Code w/PKCE and idToken") {

            let domain = URL.httpsURL(from: "samples.auth0.com")
            let method = "S256"
            let redirectURL = URL(string: "https://samples.auth0.com/callback")!
            var verifier: String!
            var challenge: String!
            var pkce: PKCE!
            var authentication: Auth0Authentication!

            beforeEach {
                verifier = "\(arc4random())"
                challenge = "\(arc4random())"
                authentication = Auth0Authentication(clientId: "CLIENT_ID", url: domain)
                pkce = PKCE(authentication: authentication, redirectURL: redirectURL, verifier: verifier, challenge: challenge, method: method, issuer: issuer, leeway: leeway, nonce: nonce)
            }

            it("shoud build credentials") {
                let token = UUID().uuidString
                let code = UUID().uuidString
                let values = ["code": code, "nonce": nonce]
                NetworkStub.addStub(condition: {
                    $0.isToken(domain.host!) && $0.hasAtLeast(["code": code, "code_verifier": pkce.verifier, "grant_type": "authorization_code", "redirect_uri": pkce.redirectURL.absoluteString])
                }, response: authResponse(accessToken: token, idToken: idToken))
                NetworkStub.addStub(condition: {
                    $0.isJWKSPath(domain.host!)
                }, response: jwksResponse())
                waitUntil { done in
                    pkce.credentials(from: values) {
                        expect($0).to(haveCredentials(token, idToken))
                        done()
                    }
                }
            }

            it("should produce id token validation failed error") {
                pkce = PKCE(authentication: authentication, redirectURL: redirectURL, verifier: verifier, challenge: challenge, method: method, issuer: issuer, leeway: leeway, nonce: nonce)
                let token = UUID().uuidString
                let code = UUID().uuidString
                let values = ["code": code, "nonce": nonce]
                let idToken = generateJWT(iss: nil, nonce: nonce).string
                let expectedError = WebAuthError(code: .idTokenValidationFailed, cause: IDTokenIssValidator.ValidationError.missingIss)
                NetworkStub.addStub(condition: {
                    $0.isToken(domain.host!) && $0.hasAtLeast(["code": code, "code_verifier": pkce.verifier, "grant_type": "authorization_code", "redirect_uri": pkce.redirectURL.absoluteString])
                }, response: authResponse(accessToken: token, idToken: idToken))
                NetworkStub.addStub(condition: {
                    $0.isJWKSPath(domain.host!)
                }, response: jwksResponse())
                waitUntil { done in
                    pkce.credentials(from: values) {
                        expect($0).to(haveWebAuthError(expectedError))
                        done()
                    }
                }
            }

            it("should produce pkce not allowed error") {
                pkce = PKCE(authentication: authentication, redirectURL: redirectURL, verifier: verifier, challenge: challenge, method: method, issuer: issuer, leeway: leeway, nonce: nonce)
                let code = UUID().uuidString
                let values = ["code": code, "nonce": nonce]
                let expectedError = WebAuthError(code: .pkceNotAllowed)
                NetworkStub.addStub(condition: {
                    $0.isToken(domain.host!) && $0.hasAtLeast(["code": code, "code_verifier": pkce.verifier, "grant_type": "authorization_code", "redirect_uri": pkce.redirectURL.absoluteString])
                }, response: authFailure(error: "foo", description: "Unauthorized"))
                waitUntil { done in
                    pkce.credentials(from: values) {
                        expect($0).to(haveWebAuthError(expectedError))
                        done()
                    }
                }
            }

            it("should produce other error") {
                pkce = PKCE(authentication: authentication, redirectURL: redirectURL, verifier: verifier, challenge: challenge, method: method, issuer: issuer, leeway: leeway, nonce: nonce)
                let code = UUID().uuidString
                let values = ["code": code, "nonce": nonce]
                let errorCode = "foo"
                let errorDescription = "bar"
                let cause = AuthenticationError(info: ["error": errorCode, "error_description": errorDescription])
                let expectedError = WebAuthError(code: .other, cause: cause)
                NetworkStub.addStub(condition: {
                    $0.isToken(domain.host!) && $0.hasAtLeast(["code": code, "code_verifier": pkce.verifier, "grant_type": "authorization_code", "redirect_uri": pkce.redirectURL.absoluteString])
                }, response: authFailure(error: errorCode, description: errorDescription))
                waitUntil { done in
                    pkce.credentials(from: values) {
                        expect($0).to(haveWebAuthError(expectedError))
                        done()
                    }
                }
            }

            it("shoud report error to get credentials") {
                waitUntil { done in
                    pkce.credentials(from: [:]) {
                        expect($0).to(beUnsuccessful())
                        done()
                    }
                }
            }

            it("should specify pkce parameters") {
                expect(pkce.defaults["code_challenge_method"]) == "S256"
                expect(pkce.defaults["code_challenge"]) == challenge
            }

            it("should get values from generator") {
                let generator = ChallengeGenerator()
                let authentication = Auth0Authentication(clientId: "CLIENT_ID", url: domain)
                pkce = PKCE(authentication: authentication, generator: generator, redirectURL: redirectURL, issuer: issuer, leeway: leeway, nonce: nonce)

                expect(pkce.defaults["code_challenge_method"]) == generator.method
                expect(pkce.defaults["code_challenge"]) == generator.challenge
                expect(pkce.verifier) == generator.verifier
            }
        }

    }
    
}
