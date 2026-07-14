import Combine
import Foundation

/// Observable, edition-agnostic change signal for optional runtime services.
///
/// Host UI can observe this object without knowing which optional module
/// supplied the services or why they changed.
@MainActor
public final class QuickMarkExtensionRuntimeState: ObservableObject {
    @Published public private(set) var revision: UInt64 = 0

    fileprivate func notifyChange() {
        revision &+= 1
    }
}

/// Process-local services supplied by an optional module.
///
/// Community builds leave this registry empty. The host never needs to import
/// or name a private package.
@MainActor
public enum QuickMarkExtensionRegistry {
    public static let runtimeState = QuickMarkExtensionRuntimeState()
    public private(set) static var customizationProviders: [any RenderCustomizationProviding] = []
    public private(set) static var exporters: [any DocumentExporting] = []

    public static func install(
        customizationProviders: [any RenderCustomizationProviding],
        exporters: [any DocumentExporting]
    ) {
        self.customizationProviders = customizationProviders
        self.exporters = exporters
        runtimeState.notifyChange()
    }

    public static func resetServices() {
        customizationProviders = []
        exporters = []
        runtimeState.notifyChange()
    }

    public static func reset() {
        customizationProviders = []
        exporters = []
        runtimeState.notifyChange()
    }
}

@MainActor
@objc public protocol QuickMarkExtensionBootstrapping {
    static func install()
}

/// Loads an optional bootstrap class named only by the official build's
/// private configuration. The Community Info.plist does not contain this key.
@MainActor
public enum QuickMarkExtensionLoader {
    public static let bootstrapInfoKey = "QuickMarkExtensionBootstrapClass"
    public static let bootstrapResourceName = "QuickMarkExtensionBootstrap"

    public static func loadConfiguredModule(from bundle: Bundle = .main) {
        let className = (bundle.object(forInfoDictionaryKey: bootstrapInfoKey) as? String)
            ?? resourceConfiguration(in: bundle)?["BootstrapClass"] as? String
        guard let className,
              !className.isEmpty,
              let bootstrap = NSClassFromString(className) as? QuickMarkExtensionBootstrapping.Type else {
            return
        }
        bootstrap.install()
    }

    private static func resourceConfiguration(in bundle: Bundle) -> [String: Any]? {
        guard let url = bundle.url(forResource: bootstrapResourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }
        return propertyList as? [String: Any]
    }
}
