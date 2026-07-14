import XCTest
@testable import QuickMarkCore

final class ExtensionRuntimeTests: XCTestCase {
    @MainActor
    func testRegistryPublishesServiceChanges() {
        let initialRevision = QuickMarkExtensionRegistry.runtimeState.revision

        QuickMarkExtensionRegistry.resetServices()
        XCTAssertEqual(
            QuickMarkExtensionRegistry.runtimeState.revision,
            initialRevision + 1
        )

        QuickMarkExtensionRegistry.reset()
        XCTAssertEqual(
            QuickMarkExtensionRegistry.runtimeState.revision,
            initialRevision + 2
        )
    }
}
