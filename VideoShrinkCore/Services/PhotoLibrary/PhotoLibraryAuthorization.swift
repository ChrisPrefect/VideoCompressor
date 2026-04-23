import Foundation
import Observation
import Photos
import os
#if canImport(UIKit)
import UIKit
#endif

/// Kapselt PhotoKit-Berechtigungsstatus und stellt komfortable Async-APIs
/// für ViewModels bereit.
@MainActor
@Observable
public final class PhotoLibraryAuthorization {

    public enum State: Equatable, Sendable {
        case notDetermined
        case denied
        case restricted
        case limited
        case authorized

        public var hasReadAccess: Bool {
            self == .authorized || self == .limited
        }

        public var displayMessage: String {
            switch self {
            case .notDetermined:
                return "VideoCompressor benötigt Zugriff auf deine Foto-Mediathek, um Videos zu analysieren und zu komprimieren."
            case .denied:
                return "Der Zugriff auf die Foto-Mediathek ist deaktiviert. Aktiviere ihn in den Systemeinstellungen, um Videos zu komprimieren."
            case .restricted:
                return "Der Zugriff auf die Foto-Mediathek ist auf diesem Gerät eingeschränkt."
            case .limited:
                return "VideoCompressor hat eingeschränkten Zugriff auf deine Foto-Mediathek. Du kannst weitere Videos zur Verarbeitung hinzufügen."
            case .authorized:
                return ""
            }
        }
    }

    public private(set) var state: State

    public init() {
        self.state = Self.translate(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func refresh() {
        self.state = Self.translate(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    @discardableResult
    public func requestAccess() async -> State {
        let raw = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let translated = Self.translate(raw)
        self.state = translated
        return translated
    }

    #if os(iOS)
    /// Im Limited-Access-Modus: Picker-Sheet, damit der Nutzer weitere
    /// Assets freigibt. Auf manchen Plattform-/Sandbox-Konfigurationen ist
    /// die Methode nicht verfügbar — wir versuchen den Aufruf reflektiv und
    /// loggen, falls er fehlschlägt.
    public func presentLimitedLibraryPicker(from controller: UIViewController) {
        guard state == .limited else { return }
        let library = PHPhotoLibrary.shared()
        let selector = NSSelectorFromString("presentLimitedLibraryPickerFromViewController:")
        if library.responds(to: selector) {
            _ = library.perform(selector, with: controller)
        } else {
            Log.app.warning("presentLimitedLibraryPicker auf dieser Plattform nicht verfügbar.")
        }
    }
    #endif

    private static func translate(_ status: PHAuthorizationStatus) -> State {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }
}
