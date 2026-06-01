import Foundation
import Crypto
import X509
import NIOSSL
@testable import RoxProxy

/// Helper for generating and managing test certificates for MITM testing.
/// 
/// Provides:
/// - Ephemeral CA generation for each test
/// - Domain certificate generation
/// - Certificate caching during test runs
///
final class CertificateTestHelper {
    
    // MARK: - Types
    
    enum CertificateError: Error, LocalizedError {
        case generationFailed(underlying: Error)
        case invalidHost
        
        var errorDescription: String? {
            switch self {
            case .generationFailed(let error):
                return "Certificate generation failed: \(error.localizedDescription)"
            case .invalidHost:
                return "Invalid hostname for certificate"
            }
        }
    }
    
    // MARK: - Properties
    
    private let ca: CertificateAuthority
    private let cache: DomainCertificateCache
    private var generatedCertificates: [String: (NIOSSLCertificate, NIOSSLPrivateKey)] = [:]
    
    // MARK: - Initialization
    
    /// Creates a test certificate helper with a new ephemeral CA
    @MainActor
    init() throws {
        self.ca = try CertificateAuthority.loadOrGenerate()
        self.cache = DomainCertificateCache(ca: ca)
    }
    
    /// Creates a test certificate helper with a custom CA
    /// - Parameter ca: Custom certificate authority to use
    init(ca: CertificateAuthority) {
        self.ca = ca
        self.cache = DomainCertificateCache(ca: ca)
    }
    
    // MARK: - CA Access
    
    /// Returns the CA certificate DER bytes
    func caCertificateDER() -> Data {
        ca.caCertificateDER()
    }
    
    /// Returns the CA certificate as NIOSSLCertificate
    func caNIOSSLCertificate() throws -> NIOSSLCertificate {
        let der = caCertificateDER()
        return try NIOSSLCertificate(bytes: Array(der), format: .der)
    }
    
    // MARK: - Domain Certificate Generation
    
    /// Generates and caches a certificate for the given hostname
    /// - Parameter host: The hostname for the certificate
    /// - Returns: Tuple of (certificate, privateKey) for NIOSSL
    func generateCertificate(for host: String) throws -> (NIOSSLCertificate, NIOSSLPrivateKey) {
        if let cached = generatedCertificates[host] {
            return cached
        }
        
        // Use the cache which handles synchronization
        let (cert, key) = try cache.certificate(for: host)
        generatedCertificates[host] = (cert, key)
        return (cert, key)
    }
    
    /// Generates a certificate directly (bypassing cache) for testing
    /// - Parameter host: The hostname for the certificate
    /// - Returns: Tuple of (certificate, privateKey) for NIOSSL
    func generateFreshCertificate(for host: String) throws -> (NIOSSLCertificate, NIOSSLPrivateKey) {
        let (cert, key) = try ca.generateDomainCertificate(for: host)
        return (cert, key)
    }
    
    // MARK: - Wildcard Certificates
    
    /// Generates a wildcard certificate for a domain
    /// - Parameter domain: The base domain (e.g., "example.com")
    /// - Returns: Tuple of (certificate, privateKey) for NIOSSL
    func generateWildcardCertificate(for domain: String) throws -> (NIOSSLCertificate, NIOSSLPrivateKey) {
        let wildcardHost = "*.\(domain)"
        return try generateCertificate(for: wildcardHost)
    }
    
    // MARK: - Certificate Validation Helpers
    
    /// Validates that a certificate is valid for the given host
    /// - Parameters:
    ///   - certificate: The certificate to validate
    ///   - host: The hostname to check
    /// - Returns: True if the certificate is valid for the host
    func validateCertificate(_ certificate: NIOSSLCertificate, for host: String) -> Bool {
        // Note: In production, use proper X509 validation
        // For testing, we just check that we generated it for this host
        return generatedCertificates[host]?.0 == certificate
    }
    
    // MARK: - Cleanup
    
    /// Clears all cached certificates
    func clearCache() {
        generatedCertificates.removeAll()
    }
    
    /// Clears a specific cached certificate
    /// - Parameter host: The hostname to clear
    func clearCertificate(for host: String) {
        generatedCertificates.removeValue(forKey: host)
    }
}

// MARK: - Static Helpers

extension CertificateTestHelper {
    /// Creates a completely ephemeral CA for a single test
    /// - Returns: Tuple of (CA, helper) that can be used for isolated tests
    static func createEphemeral() throws -> (CertificateAuthority, CertificateTestHelper) {
        let ca = try CertificateAuthority.loadOrGenerate()
        let helper = CertificateTestHelper(ca: ca)
        return (ca, helper)
    }
    
    /// Generates a self-signed certificate for testing without CA
    /// Useful for unit tests that don't need the full CA infrastructure
    static func generateSelfSignedCertificate(for host: String) throws -> (NIOSSLCertificate, NIOSSLPrivateKey) {
        // Generate P-256 key pair
        let rawKey = P256.Signing.PrivateKey()
        let privateKey = Certificate.PrivateKey(rawKey)
        let publicKey = Certificate.PublicKey(rawKey.publicKey)
        
        // Build distinguished name
        let name = try DistinguishedName {
            CommonName(host)
            OrganizationName("Rox Proxy Test")
        }
        
        // Validity: 1 hour (short-lived for tests)
        let now = Date()
        let expiry = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        
        // Extensions
        let extensions = try Certificate.Extensions {
            SubjectAlternativeNames([.dnsName(host)])
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.serverAuth])
        }
        
        // Create self-signed certificate
        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: publicKey,
            notValidBefore: now,
            notValidAfter: expiry,
            issuer: name,
            subject: name,
            extensions: extensions,
            issuerPrivateKey: privateKey
        )
        
        // Serialize to PEM
        let certPEM = try cert.serializeAsPEM().pemString
        let keyPEM = try privateKey.serializeAsPEM().pemString
        
        // Convert to NIOSSL types
        let nioSSLCert = try NIOSSLCertificate(bytes: Array(certPEM.utf8), format: .pem)
        let nioSSLKey = try NIOSSLPrivateKey(bytes: Array(keyPEM.utf8), format: .pem)
        
        return (nioSSLCert, nioSSLKey)
    }
}
