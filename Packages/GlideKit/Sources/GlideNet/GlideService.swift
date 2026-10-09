#if canImport(Network)
import Foundation
import Network
import CryptoKit
import Security

public enum GlideService {
    public static let bonjourType = "_glide._tcp"

    /// TCP with Nagle disabled, wrapped in TLS 1.2 using a pre-shared key derived from the PIN.
    /// A device that doesn't know the PIN cannot complete the handshake, and everything on the
    /// wire is encrypted.
    ///
    /// NOTE: a 6-digit PIN is a low-entropy PSK. That is acceptable for private testing, but
    /// before a public release this should become a random 128-bit key exchanged via QR code.
    public static func parameters(pin: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = Data(SHA256.hash(data: Data("glide-v1|\(pin)".utf8)))
        let identity = Data("glide".utf8)

        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
            identity.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData)
        // 0x00A8 = TLS_PSK_WITH_AES_128_GCM_SHA256. Spelled as a literal because the SDK's
        // SSLCipherSuite constant is a different integer width on different architectures,
        // which broke universal (arm64 + x86_64) Release builds.
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: 0x00A8)!)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}
#endif
