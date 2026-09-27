import AVFoundation
import XCTest
@testable import BlobbyCam

final class CameraPermissionTests: XCTestCase {
    func testMapsAVFoundationAuthorizationStatuses() {
        XCTAssertEqual(CameraPermissionStatus.map(.notDetermined), .notDetermined)
        XCTAssertEqual(CameraPermissionStatus.map(.authorized), .authorized)
        XCTAssertEqual(CameraPermissionStatus.map(.denied), .denied)
        XCTAssertEqual(CameraPermissionStatus.map(.restricted), .restricted)
        XCTAssertTrue(CameraPermissionStatus.authorized.allowsCapture)
        XCTAssertFalse(CameraPermissionStatus.denied.allowsCapture)
        XCTAssertFalse(CameraPermissionStatus.restricted.allowsCapture)
        XCTAssertFalse(CameraPermissionStatus.notDetermined.allowsCapture)
    }

    @MainActor
    func testDoesNotPromptWhenAccessIsAlreadyResolved() {
        let provider = FakeCameraAuthorizationProvider(status: .authorized)
        let permission = CameraPermission(authorization: provider)
        var receivedStatus: CameraPermissionStatus?

        permission.requestAccessIfNeeded { receivedStatus = $0 }

        XCTAssertEqual(receivedStatus, .authorized)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertTrue(permission.status.allowsCapture)
    }

    @MainActor
    func testConcurrentRequestsShareOneSystemPromptAndReportGrant() async {
        let provider = FakeCameraAuthorizationProvider(status: .notDetermined)
        let permission = CameraPermission(authorization: provider)
        let bothCallbacksCompleted = expectation(description: "both callers receive the result")
        bothCallbacksCompleted.expectedFulfillmentCount = 2
        var results: [CameraPermissionStatus] = []

        permission.requestAccessIfNeeded {
            results.append($0)
            bothCallbacksCompleted.fulfill()
        }
        permission.requestAccessIfNeeded {
            results.append($0)
            bothCallbacksCompleted.fulfill()
        }

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertTrue(results.isEmpty)

        provider.resolve(granted: true, as: .authorized)
        await fulfillment(of: [bothCallbacksCompleted], timeout: 2)

        XCTAssertEqual(results, [.authorized, .authorized])
        XCTAssertEqual(permission.status, .authorized)
        XCTAssertEqual(provider.requestCount, 1)
    }

    @MainActor
    func testDenialRemainsNoncapturingAndDoesNotPromptAgain() async {
        let provider = FakeCameraAuthorizationProvider(status: .notDetermined)
        let permission = CameraPermission(authorization: provider)
        let firstResult = expectation(description: "denial result")
        var receivedStatuses: [CameraPermissionStatus] = []

        permission.requestAccessIfNeeded {
            receivedStatuses.append($0)
            firstResult.fulfill()
        }
        provider.resolve(granted: false, as: .denied)
        await fulfillment(of: [firstResult], timeout: 2)

        var secondResult: CameraPermissionStatus?
        permission.requestAccessIfNeeded { secondResult = $0 }

        XCTAssertEqual(receivedStatuses, [.denied])
        XCTAssertEqual(secondResult, .denied)
        XCTAssertEqual(permission.status, .denied)
        XCTAssertFalse(permission.status.allowsCapture)
        XCTAssertEqual(provider.requestCount, 1)
    }

    @MainActor
    func testRestrictedStatusIsStableAndNoncapturing() {
        let provider = FakeCameraAuthorizationProvider(status: .restricted)
        let permission = CameraPermission(authorization: provider)
        var receivedStatus: CameraPermissionStatus?

        permission.requestAccessIfNeeded { receivedStatus = $0 }

        XCTAssertEqual(receivedStatus, .restricted)
        XCTAssertFalse(permission.status.allowsCapture)
        XCTAssertEqual(provider.requestCount, 0)
    }
}

@MainActor
private final class FakeCameraAuthorizationProvider: CameraAuthorizationProviding {
    private(set) var videoAuthorizationStatus: AVAuthorizationStatus
    private(set) var requestCount = 0
    private var requestCompletion: (@Sendable (Bool) -> Void)?

    init(status: AVAuthorizationStatus) {
        videoAuthorizationStatus = status
    }

    func requestVideoAccess(completion: @escaping @Sendable (Bool) -> Void) {
        requestCount += 1
        requestCompletion = completion
    }

    func resolve(granted: Bool, as status: AVAuthorizationStatus) {
        videoAuthorizationStatus = status
        let completion = requestCompletion
        requestCompletion = nil
        completion?(granted)
    }
}
