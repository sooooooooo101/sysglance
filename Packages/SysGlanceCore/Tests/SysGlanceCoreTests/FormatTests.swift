import Foundation
import Testing
@testable import SysGlanceCore

@Suite struct FormatTests {
    @Test(arguments: [
        (UInt64(0), "0 B"),
        (UInt64(999), "999 B"),
        (UInt64(1_000), "1.0 KB"),
        (UInt64(1_500), "1.5 KB"),
        (UInt64(999_600), "1.0 MB"),
        (UInt64(245_107_195_904), "245 GB"),
        (UInt64(25_592_918_572), "25.6 GB"),
    ])
    func decimalBytes(value: UInt64, expected: String) {
        #expect(Fmt.bytes(value, base: .decimal) == expected)
    }

    @Test(arguments: [
        (UInt64(17_179_869_184), "16.0 GB"),
        (UInt64(1_048_576), "1.0 MB"),
        (UInt64(1_023 * 1_024), "1.0 MB"),
        (UInt64(512), "512 B"),
    ])
    func binaryBytes(value: UInt64, expected: String) {
        #expect(Fmt.bytes(value, base: .binary) == expected)
    }

    @Test func rateClampsNegativeAndNonFinite() {
        #expect(Fmt.rate(1_234_567) == "1.2 MB/s")
        #expect(Fmt.rate(-5) == "0 B/s")
        #expect(Fmt.rate(.nan) == "0 B/s")
        #expect(Fmt.rate(.infinity) == "0 B/s")
    }

    @Test func percent() {
        #expect(Fmt.percent(0.424) == "42%")
        #expect(Fmt.percent(0.425) == "43%")
        #expect(Fmt.percent(1.7) == "100%")
        #expect(Fmt.percent(-1) == "0%")
    }

    @Test func duration() {
        #expect(Fmt.duration(59) == "0分")
        #expect(Fmt.duration(12 * 60) == "12分")
        #expect(Fmt.duration(4 * 3600 + 12 * 60) == "4時間 12分")
        #expect(Fmt.duration(3 * 86400 + 4 * 3600 + 59 * 60) == "3日 4時間")
        #expect(Fmt.duration(-10) == "0分")
    }

    @Test func ago() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(Fmt.ago(from: now.addingTimeInterval(-30), now: now) == "たった今")
        #expect(Fmt.ago(from: now.addingTimeInterval(-180), now: now) == "3分前")
        #expect(Fmt.ago(from: now.addingTimeInterval(-7_300), now: now) == "2時間前")
    }
}
