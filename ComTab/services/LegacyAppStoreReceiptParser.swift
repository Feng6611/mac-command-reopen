//
//  LegacyAppStoreReceiptParser.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import Security

struct LegacyAppStoreReceipt: Equatable, Sendable {
    let originalAppVersion: String

    nonisolated init(originalAppVersion: String) {
        self.originalAppVersion = originalAppVersion
    }

    nonisolated static func == (lhs: LegacyAppStoreReceipt, rhs: LegacyAppStoreReceipt) -> Bool {
        lhs.originalAppVersion == rhs.originalAppVersion
    }
}

enum LegacyAppStoreReceiptParser {
    private enum AttributeType {
        static let originalAppVersion = 19
    }

    static func extractPayload(fromSignedReceiptData receiptData: Data) throws -> Data {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else {
            throw ReceiptDecodingError.cmsDecoderCreateFailed
        }

        let updateStatus = receiptData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else {
                return errSecParam
            }

            return CMSDecoderUpdateMessage(decoder, baseAddress, receiptData.count)
        }

        guard updateStatus == errSecSuccess else {
            throw ReceiptDecodingError.cmsDecoderUpdateFailed(updateStatus)
        }

        let finalizeStatus = CMSDecoderFinalizeMessage(decoder)
        guard finalizeStatus == errSecSuccess else {
            throw ReceiptDecodingError.cmsDecoderFinalizeFailed(finalizeStatus)
        }

        var payloadDataReference: CFData?
        let copyStatus = CMSDecoderCopyContent(decoder, &payloadDataReference)
        guard copyStatus == errSecSuccess, let payloadDataReference else {
            throw ReceiptDecodingError.cmsDecoderCopyContentFailed(copyStatus)
        }

        return payloadDataReference as Data
    }

    static func parse(payloadData: Data) throws -> LegacyAppStoreReceipt {
        let rootNode = try ASN1Node.parse(from: payloadData, startingAt: payloadData.startIndex)
        guard rootNode.tag == .set else {
            throw ReceiptDecodingError.unexpectedASN1Tag(expected: .set, actual: rootNode.tag.rawValue)
        }

        var originalAppVersion: String?
        var attributeCursor = rootNode.valueRange.lowerBound

        while attributeCursor < rootNode.valueRange.upperBound {
            let attributeNode = try ASN1Node.parse(from: payloadData, startingAt: attributeCursor)
            guard attributeNode.tag == .sequence else {
                throw ReceiptDecodingError.unexpectedASN1Tag(expected: .sequence, actual: attributeNode.tag.rawValue)
            }

            let attributeData = payloadData[attributeNode.valueRange]
            let attribute = try parseAttribute(from: Data(attributeData))
            if attribute.type == AttributeType.originalAppVersion {
                originalAppVersion = try decodeString(fromWrappedASN1Data: attribute.value)
            }

            attributeCursor = attributeNode.nextOffset
        }

        guard let originalAppVersion else {
            throw ReceiptDecodingError.missingOriginalAppVersion
        }

        return LegacyAppStoreReceipt(originalAppVersion: originalAppVersion)
    }

    private static func parseAttribute(from attributeData: Data) throws -> ParsedReceiptAttribute {
        let typeNode = try ASN1Node.parse(from: attributeData, startingAt: attributeData.startIndex)
        guard typeNode.tag == .integer else {
            throw ReceiptDecodingError.unexpectedASN1Tag(expected: .integer, actual: typeNode.tag.rawValue)
        }

        let versionNode = try ASN1Node.parse(from: attributeData, startingAt: typeNode.nextOffset)
        guard versionNode.tag == .integer else {
            throw ReceiptDecodingError.unexpectedASN1Tag(expected: .integer, actual: versionNode.tag.rawValue)
        }

        let valueNode = try ASN1Node.parse(from: attributeData, startingAt: versionNode.nextOffset)
        guard valueNode.tag == .octetString else {
            throw ReceiptDecodingError.unexpectedASN1Tag(expected: .octetString, actual: valueNode.tag.rawValue)
        }

        return ParsedReceiptAttribute(
            type: try decodeInteger(from: attributeData[typeNode.valueRange]),
            value: Data(attributeData[valueNode.valueRange])
        )
    }

    private static func decodeInteger(from data: Data) throws -> Int {
        guard !data.isEmpty else {
            throw ReceiptDecodingError.invalidInteger
        }

        return data.reduce(0) { partialResult, byte in
            (partialResult << 8) | Int(byte)
        }
    }

    private static func decodeString(fromWrappedASN1Data data: Data) throws -> String {
        let node = try ASN1Node.parse(from: data, startingAt: data.startIndex)
        switch node.tag {
        case .utf8String, .ia5String:
            guard let string = String(data: data[node.valueRange], encoding: .utf8) else {
                throw ReceiptDecodingError.invalidStringEncoding
            }

            return string
        default:
            throw ReceiptDecodingError.unexpectedASN1Tag(expected: ASN1Tag.utf8String, actual: node.tag.rawValue)
        }
    }
}

private struct ParsedReceiptAttribute {
    let type: Int
    let value: Data
}

enum ASN1Tag: UInt8 {
    case integer = 0x02
    case octetString = 0x04
    case ia5String = 0x16
    case utf8String = 0x0C
    case sequence = 0x30
    case set = 0x31
}

private struct ASN1Node {
    let tag: ASN1Tag
    let valueRange: Range<Int>
    let nextOffset: Int

    static func parse(from data: Data, startingAt offset: Int) throws -> ASN1Node {
        guard offset < data.endIndex else {
            throw ReceiptDecodingError.truncatedASN1
        }

        guard let tag = ASN1Tag(rawValue: data[offset]) else {
            throw ReceiptDecodingError.unknownASN1Tag(data[offset])
        }

        let lengthOffset = offset + 1
        let (length, valueOffset) = try parseLength(from: data, startingAt: lengthOffset)
        let valueEnd = valueOffset + length

        guard valueEnd <= data.endIndex else {
            throw ReceiptDecodingError.truncatedASN1
        }

        return ASN1Node(
            tag: tag,
            valueRange: valueOffset..<valueEnd,
            nextOffset: valueEnd
        )
    }

    private static func parseLength(from data: Data, startingAt offset: Int) throws -> (Int, Int) {
        guard offset < data.endIndex else {
            throw ReceiptDecodingError.truncatedASN1
        }

        let firstByte = data[offset]
        if firstByte & 0x80 == 0 {
            return (Int(firstByte), offset + 1)
        }

        let byteCount = Int(firstByte & 0x7F)
        guard byteCount > 0 else {
            throw ReceiptDecodingError.unsupportedASN1Length
        }

        let lengthStart = offset + 1
        let lengthEnd = lengthStart + byteCount
        guard lengthEnd <= data.endIndex else {
            throw ReceiptDecodingError.truncatedASN1
        }

        let length = data[lengthStart..<lengthEnd].reduce(0) { partialResult, byte in
            (partialResult << 8) | Int(byte)
        }

        return (length, lengthEnd)
    }
}

enum ReceiptDecodingError: LocalizedError, Equatable {
    case cmsDecoderCreateFailed
    case cmsDecoderUpdateFailed(OSStatus)
    case cmsDecoderFinalizeFailed(OSStatus)
    case cmsDecoderCopyContentFailed(OSStatus)
    case truncatedASN1
    case unsupportedASN1Length
    case unknownASN1Tag(UInt8)
    case unexpectedASN1Tag(expected: ASN1Tag, actual: UInt8)
    case invalidInteger
    case invalidStringEncoding
    case missingOriginalAppVersion

    var errorDescription: String? {
        switch self {
        case .cmsDecoderCreateFailed:
            return "Could not create CMS decoder."
        case .cmsDecoderUpdateFailed(let status):
            return "Could not decode signed App Store receipt. status=\(status)"
        case .cmsDecoderFinalizeFailed(let status):
            return "Could not finalize signed App Store receipt. status=\(status)"
        case .cmsDecoderCopyContentFailed(let status):
            return "Could not extract App Store receipt payload. status=\(status)"
        case .truncatedASN1:
            return "Receipt ASN.1 payload was truncated."
        case .unsupportedASN1Length:
            return "Receipt ASN.1 payload used an unsupported length encoding."
        case .unknownASN1Tag(let tag):
            return "Receipt ASN.1 payload used an unknown tag \(tag)."
        case .unexpectedASN1Tag(let expected, let actual):
            return "Receipt ASN.1 payload expected tag \(expected.rawValue) but found \(actual)."
        case .invalidInteger:
            return "Receipt ASN.1 integer was invalid."
        case .invalidStringEncoding:
            return "Receipt ASN.1 string could not be decoded as UTF-8."
        case .missingOriginalAppVersion:
            return "Receipt did not contain original_application_version."
        }
    }
}
