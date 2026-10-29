import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UIKit

nonisolated enum PINStore {
    private static let service = "abc.CashLoanManagement.pin"
    private static let account = "pin"

    static var isSet: Bool { read() != nil }

    static func set(_ pin: String) throws {
        let data = Data(hash(pin).utf8)
        SecItemDelete(baseQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError("Couldn't save the PIN.") }
    }

    static func matches(_ pin: String) -> Bool {
        read() == hash(pin)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func hash(_ pin: String) -> String {
        SHA256.hash(data: Data(pin.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum ImageStore {
    static func save(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else { throw AppError("That photo couldn't be read.") }
        let scaled = scale(image, maxDimension: 1600)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.8) else {
            throw AppError("That photo couldn't be saved.")
        }
        let url = try folder().appendingPathComponent(UUID().uuidString + ".jpg")
        try jpeg.write(to: url, options: .atomic)
        return url.path
    }

    static func image(at path: String) -> UIImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    static func deleteIfOwned(_ path: String) {
        guard let folder = try? folder() else { return }
        let file = URL(fileURLWithPath: path).standardizedFileURL
        let root = folder.standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { return }
        try? FileManager.default.removeItem(at: file)
    }

    private static func folder() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func scale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension, largest > 0 else { return image }
        let ratio = maxDimension / largest
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

@Observable
final class LockService {
    private(set) var isEnabled: Bool
    var biometricsEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricsEnabled, forKey: Keys.biometrics) }
    }
    var isLocked: Bool

    init(useKeychain: Bool = true) {
        if useKeychain {
            isEnabled = PINStore.isSet
            biometricsEnabled = UserDefaults.standard.bool(forKey: Keys.biometrics)
            isLocked = PINStore.isSet
        } else {
            isEnabled = false
            biometricsEnabled = false
            isLocked = false
        }
    }

    static func preview() -> LockService {
        LockService(useKeychain: false)
    }

    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    func unlock(pin: String) -> Bool {
        guard PINStore.matches(pin) else { return false }
        isLocked = false
        return true
    }

    func unlockWithBiometrics() async -> Bool {
        guard biometricsEnabled, await authenticate() else { return false }
        isLocked = false
        return true
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        do {
            return try await withCheckedThrowingContinuation { continuation in
                context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Unlock your loans and cash records."
                ) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
        } catch {
            return false
        }
    }

    func setPIN(_ pin: String) throws {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { throw AppError("Use a 4-digit PIN.") }
        try PINStore.set(pin)
        isEnabled = true
    }

    func removePIN(_ pin: String) -> Bool {
        guard PINStore.matches(pin) else { return false }
        PINStore.clear()
        biometricsEnabled = false
        isEnabled = false
        isLocked = false
        return true
    }

    func changePIN(current: String, newPIN: String) throws -> Bool {
        guard PINStore.matches(current) else { return false }
        try setPIN(newPIN)
        return true
    }
}

private enum Keys {
    static let biometrics = "biometricsEnabled"
}
