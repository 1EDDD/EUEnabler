import Foundation
import SwiftUI

@MainActor
final class EligibilityManager: ObservableObject {
    @Published private(set) var statusMessage = "Ready to check access."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false

    static let eligibilityDirectory =
        "/var/containers/Shared/SystemGroup/systemgroup.com.apple.eligibility"
    static let eligibilityPath = eligibilityDirectory + "/eligibility.plist"

    private var backupURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("EUEnabler-eligibility-original.plist")
    }

    var systemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    var isSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    func apply() {
        guard !isWorking else { return }
        guard isSupported else {
            errorMessage = "This build requires iOS 27 or later."
            statusMessage = "Unsupported operating system."
            return
        }

        isWorking = true
        errorMessage = nil
        statusMessage = "Checking SystemGroup access…"
        defer { isWorking = false }

        do {
            let access = try EUWQAccessToken.grant(directory: Self.eligibilityDirectory)
            defer { _ = access }

            let destinationURL = URL(fileURLWithPath: Self.eligibilityPath)
            let original = try Data(contentsOf: destinationURL, options: [.mappedIfSafe])
            guard !original.isEmpty else {
                throw ManagerError.emptyEligibilityFile
            }

            var sourceFormat = PropertyListSerialization.PropertyListFormat.xml
            let sourceObject = try PropertyListSerialization.propertyList(
                from: original,
                options: [],
                format: &sourceFormat
            )
            guard var current = sourceObject as? [String: Any] else {
                throw ManagerError.invalidEligibilityFile
            }

            guard let patchURL = Bundle.main.url(forResource: "eligibility", withExtension: "plist") else {
                throw ManagerError.missingPatch
            }
            let patchData = try Data(contentsOf: patchURL)
            var patchFormat = PropertyListSerialization.PropertyListFormat.xml
            let patchObject = try PropertyListSerialization.propertyList(
                from: patchData,
                options: [],
                format: &patchFormat
            )
            guard let patch = patchObject as? [String: Any] else {
                throw ManagerError.invalidPatch
            }

            let domainKeys = patch.keys.filter { $0.hasPrefix("OS_ELIGIBILITY_DOMAIN_") }
            guard !domainKeys.isEmpty else {
                throw ManagerError.emptyPatch
            }

            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try original.write(to: backupURL, options: [.atomic])
            }

            for key in domainKeys {
                current[key] = patch[key]
            }

            let output = try PropertyListSerialization.data(
                fromPropertyList: current,
                format: sourceFormat,
                options: 0
            )

            do {
                try output.write(to: destinationURL, options: [.atomic])
                let readBack = try Data(contentsOf: destinationURL, options: [.mappedIfSafe])
                guard readBack == output else {
                    throw ManagerError.verificationFailed
                }
            } catch {
                try? original.write(to: destinationURL, options: [.atomic])
                throw error
            }

            statusMessage = "Applied (domainKeys.count) eligibility domains. Original file backed up."
            errorMessage = nil
        } catch {
            statusMessage = "Could not apply eligibility changes."
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                throw ManagerError.noBackup
            }
            let access = try EUWQAccessToken.grant(directory: Self.eligibilityDirectory)
            defer { _ = access }

            let original = try Data(contentsOf: backupURL, options: [.mappedIfSafe])
            let destinationURL = URL(fileURLWithPath: Self.eligibilityPath)
            try original.write(to: destinationURL, options: [.atomic])
            let readBack = try Data(contentsOf: destinationURL, options: [.mappedIfSafe])
            guard readBack == original else {
                throw ManagerError.verificationFailed
            }

            statusMessage = "Original eligibility file restored."
        } catch {
            statusMessage = "Could not restore the original file."
            errorMessage = error.localizedDescription
        }
    }
}

private enum ManagerError: LocalizedError {
    case emptyEligibilityFile
    case invalidEligibilityFile
    case missingPatch
    case invalidPatch
    case emptyPatch
    case verificationFailed
    case noBackup

    var errorDescription: String? {
        switch self {
        case .emptyEligibilityFile:
            return "The system eligibility file is empty."
        case .invalidEligibilityFile:
            return "The system eligibility file is not a valid property list."
        case .missingPatch:
            return "The bundled eligibility patch is missing."
        case .invalidPatch:
            return "The bundled eligibility patch is not a valid property list."
        case .emptyPatch:
            return "No eligibility domains were found in the bundled patch."
        case .verificationFailed:
            return "The saved file did not match the requested data."
        case .noBackup:
            return "No original eligibility backup exists in this app."
        }
    }
}
