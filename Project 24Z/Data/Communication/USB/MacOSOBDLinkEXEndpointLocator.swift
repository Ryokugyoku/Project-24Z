#if os(macOS)
import Foundation
import IOKit
import IOKit.serial

/// IOKit Registryから実測済みOBDLink EX Descriptorに完全一致するcallout endpointだけを返します。
nonisolated struct MacOSOBDLinkEXEndpointLocator: USBSerialEndpointLocating, Sendable {
    /// ScanTool.net OBDLink EXとして実測したUSB Vendor IDです。
    private static let approvedVendorID = 0x0403

    /// ScanTool.net OBDLink EXとして実測したUSB Product IDです。
    private static let approvedProductID = 0x6015

    /// Descriptorの完全一致を要求してendpointを列挙します。
    /// - Returns: VID、PID、Product nameが一致するcallout endpoint。
    /// - Throws: IOKit列挙を開始できない場合は`transportUnavailable`。
    func locateApprovedEndpoints() throws -> [TransportEndpoint] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else {
            throw CommunicationRuntimeError.transportUnavailable
        }
        (matching as NSMutableDictionary)[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw CommunicationRuntimeError.transportUnavailable
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [(endpoint: TransportEndpoint, isApproved: Bool)] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = stringProperty(kIOCalloutDeviceKey, on: service),
                  isEligibleUSBSerialPath(path) else {
                continue
            }
            candidates.append(
                (
                    endpoint: TransportEndpoint(identifier: path, kind: .usbSerial),
                    isApproved: approvedDescriptorExists(from: service)
                )
            )
        }
        guard candidates.count == 1,
              let candidate = candidates.first,
              candidate.isApproved else {
            return []
        }
        return [candidate.endpoint]
    }

    /// Runbook事前確認と同じ除外規則でUSB serial候補を数えます。
    /// - Parameter path: IOKitが返したcallout device path。
    /// - Returns: Bluetooth incoming、debug console、wlan debug以外なら`true`。
    private func isEligibleUSBSerialPath(_ path: String) -> Bool {
        !path.hasSuffix(".Bluetooth-Incoming-Port")
            && !path.hasSuffix(".debug-console")
            && !path.hasSuffix(".wlan-debug")
    }

    /// Serial serviceからUSB祖先をたどり、VID／PID／Productを同じRegistry nodeで照合します。
    /// - Parameter service: IOSerialBSDClient service。
    /// - Returns: 承認済みDescriptorを持つ祖先が存在する場合は`true`。
    private func approvedDescriptorExists(from service: io_registry_entry_t) -> Bool {
        var current = service
        var ownedCurrent = false
        defer {
            if ownedCurrent { IOObjectRelease(current) }
        }

        for _ in 0..<12 {
            let vendor = integerProperty("idVendor", on: current)
            let product = integerProperty("idProduct", on: current)
            let productName = stringProperty("USB Product Name", on: current)
                ?? stringProperty("kUSBProductString", on: current)
            if vendor == Self.approvedVendorID,
               product == Self.approvedProductID,
               productName == "OBDLink EX" {
                return true
            }

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return false
            }
            if ownedCurrent { IOObjectRelease(current) }
            current = parent
            ownedCurrent = true
        }
        return false
    }

    /// Registry文字列propertyを安全に読みます。
    /// - Parameters:
    ///   - key: Registry property key。
    ///   - entry: 読取対象entry。
    /// - Returns: String property。型不一致または不存在なら`nil`。
    private func stringProperty(_ key: String, on entry: io_registry_entry_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    /// Registry数値propertyを安全に読みます。
    /// - Parameters:
    ///   - key: Registry property key。
    ///   - entry: 読取対象entry。
    /// - Returns: Int property。型不一致または不存在なら`nil`。
    private func integerProperty(_ key: String, on entry: io_registry_entry_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }
}
#endif
