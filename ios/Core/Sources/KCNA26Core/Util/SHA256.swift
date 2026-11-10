import Foundation

/// SHA-256 (FIPS 180-4) in plain Swift, for the data manifest checks (Kotlin
/// `MessageDigest.getInstance("SHA-256")`). CryptoKit is not available on Linux, and the
/// digests are only a few MB per data set, so a straightforward implementation is enough.
///
/// ```swift
/// SHA256.hex(data)   // "ba7816bf..." (lowercase, Kotlin DataManifest.sha256)
/// ```
enum SHA256 {
    /// The 32-byte digest of `data`.
    static func digest(_ data: Data) -> [UInt8] {
        data.withUnsafeBytes { raw in digest(raw.bindMemory(to: UInt8.self)) }
    }

    /// The 32-byte digest of `bytes`.
    static func digest(_ bytes: [UInt8]) -> [UInt8] {
        bytes.withUnsafeBufferPointer { digest($0) }
    }

    /// Lowercase hex of the digest (Kotlin `joinToString("") { "%02x".format(it) }`).
    static func hex(_ data: Data) -> String { hexString(digest(data)) }

    /// Lowercase hex of the digest of a string's UTF-8 bytes.
    static func hex(_ string: String) -> String { hexString(digest(Array(string.utf8))) }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private static func digest(_ input: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var w = [UInt32](repeating: 0, count: 64)
        var block = [UInt8](repeating: 0, count: 64)

        func process(_ b: UnsafeBufferPointer<UInt8>) {
            for t in 0..<16 {
                let i = t * 4
                w[t] = UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
            }
            for t in 16..<64 {
                let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var a = h[0], bb = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for t in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[t] &+ w[t]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & bb) ^ (a & c) ^ (bb & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1
                d = c; c = bb; bb = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ bb; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }

        let n = input.count
        var off = 0
        while off + 64 <= n {
            process(UnsafeBufferPointer(rebasing: input[off..<(off + 64)]))
            off += 64
        }
        // Padding: the rest, 0x80, zeros, then the bit length (big-endian) in the last 8 bytes.
        let rest = n - off
        for i in 0..<rest { block[i] = input[off + i] }
        block[rest] = 0x80
        for i in (rest + 1)..<64 { block[i] = 0 }
        if rest >= 56 {
            block.withUnsafeBufferPointer { process($0) }
            for i in 0..<64 { block[i] = 0 }
        }
        let bits = UInt64(n) &* 8
        for i in 0..<8 { block[56 + i] = UInt8(truncatingIfNeeded: bits >> (56 - 8 * UInt64(i))) }
        block.withUnsafeBufferPointer { process($0) }

        var out: [UInt8] = []
        out.reserveCapacity(32)
        for v in h {
            out.append(UInt8(truncatingIfNeeded: v >> 24))
            out.append(UInt8(truncatingIfNeeded: v >> 16))
            out.append(UInt8(truncatingIfNeeded: v >> 8))
            out.append(UInt8(truncatingIfNeeded: v))
        }
        return out
    }

    @inline(__always)
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    private static func hexString(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
