import Foundation

/// Accepts the self-signed certificate a Samsung TV presents on port 8002.
///
/// Every Samsung set ships the same "SmartViewSDK" self-signed root, so there is no
/// real chain to validate. Trust is therefore scoped as tightly as it can be: only a
/// server-trust challenge from the exact host this delegate was built for is accepted,
/// and everything else falls through to default handling.
final class TVTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let host: String

    init(host: String) {
        self.host = host
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
