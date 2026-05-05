import Foundation
import XCTest
@testable import RevenueCatCommerceKit

final class LegacyAppStoreReceiptParserTests: XCTestCase {
    func testReceiptParserExtractsOriginalAppVersionFromPayload() throws {
        let payload = makeReceiptPayload(originalAppVersion: "1.1.0")

        let receipt = try LegacyAppStoreReceiptParser.parse(payloadData: payload)

        XCTAssertEqual(receipt, .init(originalAppVersion: "1.1.0"))
    }

    func testReceiptParserRejectsPayloadsWithoutOriginalAppVersion() throws {
        let payload = wrap(tag: 0x31, content: Data())

        XCTAssertThrowsError(try LegacyAppStoreReceiptParser.parse(payloadData: payload)) { error in
            XCTAssertEqual(error as? ReceiptDecodingError, .missingOriginalAppVersion)
        }
    }

    private func makeReceiptPayload(originalAppVersion: String) -> Data {
        let value = wrap(tag: 0x04, content: wrap(tag: 0x0C, content: Data(originalAppVersion.utf8)))
        let attribute = wrap(
            tag: 0x30,
            content: encodeInteger(19) + encodeInteger(1) + value
        )

        return wrap(tag: 0x31, content: attribute)
    }

    private func encodeInteger(_ value: Int) -> Data {
        wrap(tag: 0x02, content: Data([UInt8(value)]))
    }

    private func wrap(tag: UInt8, content: Data) -> Data {
        Data([tag]) + encodeLength(content.count) + content
    }

    private func encodeLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        let bytes = withUnsafeBytes(of: UInt32(length).bigEndian) { rawBuffer in
            Data(rawBuffer.drop { $0 == 0 })
        }

        return Data([0x80 | UInt8(bytes.count)]) + bytes
    }
}
