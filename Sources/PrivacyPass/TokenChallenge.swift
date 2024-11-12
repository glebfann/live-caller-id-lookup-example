// Copyright 2024 Apple Inc. and the Swift Homomorphic Encryption project authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Privacy Pass Token Challenge.
///
/// This is the token request struct.
/// ```
/// struct {
///     uint16_t token_type;
///     opaque issuer_name<1..2^16-1>;
///     opaque redemption_context<0..32>;
///     opaque origin_info<0..2^16-1>;
/// } TokenChallenge;
/// ```
/// - seealso: [RFC 9577: Token Challenge](https://www.rfc-editor.org/rfc/rfc9577#name-token-challenge)
public struct TokenChallenge: Equatable, Sendable {
    public static let blindedMsgSize = TokenTypeBlindRSANK
    public static let minSizeInBytes = MemoryLayout<UInt16>.size + MemoryLayout<UInt16>.size + MemoryLayout<UInt8>
        .size + MemoryLayout<UInt16>.size

    /// Token type.
    public let tokenType: UInt16
    /// An ASCII string that identifies the Issuer, using the format of a server name as defined in
    /// <https://www.rfc-editor.org/rfc/rfc9577#server-name> .
    public let issuer: String
    /// Redemption context, either a 0 or 32 byte value generated by the Origin that allows the Origin to require that
    /// clients fetch tokens bound to a specific context.
    public let redemptionContext: [UInt8]
    /// Contains Origin names that allows a token to be scoped to a specific set of Origins.
    public let originInfo: [String]

    /// Constructs a new TokenChallenge.
    ///
    /// - Warning: Does not validate that `issuer` and `originInfo` fields are in correct format as specified in
    /// <https://www.rfc-editor.org/rfc/rfc9577#server-name>.
    /// - Parameters:
    ///   - tokenType: Token type.
    ///   - issuer: An ASCII string that identifies the Issuer, using the format of a server name as defined in
    /// <https://www.rfc-editor.org/rfc/rfc9577#server-name>.
    ///   - redemptionContext: Redemption context, either a 0 or 32 byte value generated by the Origin that allows the
    /// Origin to require that Clients fetch tokens bound to a specific context.
    ///   - originInfo: Contains Origin names that allows a token to be scoped to a specific set of Origins. Each server
    /// name must be in format defined in <https://www.rfc-editor.org/rfc/rfc9577#server-name>.
    /// - seealso: [RFC 9577: Token Challenge](https://www.rfc-editor.org/rfc/rfc9577#name-token-challenge)
    public init(tokenType: UInt16, issuer: String, redemptionContext: [UInt8] = [], originInfo: [String] = []) throws {
        guard redemptionContext.isEmpty || redemptionContext.count == 32 else {
            throw PrivacyPassError(code: .invalidRedemptionContext)
        }
        self.tokenType = tokenType
        self.issuer = issuer
        self.redemptionContext = redemptionContext
        self.originInfo = originInfo
    }

    /// Load a Private Pass Token Challenge from bytes.
    ///
    /// - Warning: Does not validate that `issuer` and `originInfo` fields are in correct format as specified in
    /// <https://www.rfc-editor.org/rfc/rfc9577#server-name>.
    /// - Parameter bytes: Collection of bytes representing a token challenge.
    public init<C: Collection<UInt8>>(from bytes: C) throws {
        guard bytes.count >= Self.minSizeInBytes else {
            throw PrivacyPassError(code: .invalidTokenChallengeSize)
        }
        var offset = bytes.startIndex

        func extractBytes(count: Int) throws -> C.SubSequence {
            let end = bytes.index(offset, offsetBy: count)
            guard end <= bytes.endIndex else {
                throw PrivacyPassError(code: .invalidTokenChallenge)
            }
            defer {
                offset = end
            }
            return bytes[offset..<end]
        }

        self.tokenType = try UInt16(bigEndianBytes: extractBytes(count: MemoryLayout<UInt16>.size))
        let issuerCount = try UInt16(bigEndianBytes: extractBytes(count: MemoryLayout<UInt16>.size))
        let issuerBytes = try extractBytes(count: Int(issuerCount))
        let redemptionContextCount = bytes[offset]
        bytes.formIndex(after: &offset)

        self.redemptionContext = try Array(extractBytes(count: Int(redemptionContextCount)))
        let originInfoCount = try UInt16(bigEndianBytes: extractBytes(count: MemoryLayout<UInt16>.size))
        let originInfoBytes = try extractBytes(count: Int(originInfoCount))
        guard offset == bytes.endIndex else {
            throw PrivacyPassError(code: .invalidTokenChallengeSize)
        }

        guard let issuer = String(bytes: Array(issuerBytes), encoding: .ascii),
              let originInfoConcatenated = String(bytes: originInfoBytes, encoding: .ascii)
        else {
            throw PrivacyPassError(code: .invalidTokenChallenge)
        }

        let originInfo = originInfoConcatenated.split(separator: ",")
        self.issuer = issuer
        self.originInfo = originInfo.map(String.init)
    }

    /// Convert to byte array.
    /// - Returns: A binary representation of the token challenge.
    public func bytes() throws -> [UInt8] {
        guard let issuerAscii = issuer.data(using: .ascii) else {
            throw PrivacyPassError(code: .invalidIssuer)
        }

        let originInfoConcatenated = originInfo.joined(separator: ",")
        guard let originInfoAscii = originInfoConcatenated.data(using: .ascii) else {
            throw PrivacyPassError(code: .invalidOriginInfo)
        }

        var bytes: [UInt8] = []
        let size = Self.minSizeInBytes + issuerAscii.count + redemptionContext.count + originInfoAscii.count
        bytes.reserveCapacity(size)
        bytes.append(contentsOf: tokenType.bigEndianBytes)
        bytes.append(contentsOf: UInt16(issuerAscii.count).bigEndianBytes)
        bytes.append(contentsOf: issuerAscii)
        bytes.append(UInt8(redemptionContext.count))
        bytes.append(contentsOf: redemptionContext)
        bytes.append(contentsOf: UInt16(originInfoAscii.count).bigEndianBytes)
        bytes.append(contentsOf: originInfoAscii)

        precondition(bytes.count == size)
        return bytes
    }
}