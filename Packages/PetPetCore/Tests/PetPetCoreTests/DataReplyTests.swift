import XCTest
@testable import PetPetCore

@MainActor final class DataReplyTests: XCTestCase {
    func testImmediateSuccessAndDuplicateCallbacksResumeOnlyOnce() async throws {
        let value = try await DataReply.wait(timeout: .milliseconds(30)) { complete in
            complete(.success(Data([1])))
            complete(.failure(BackendError.network))
            complete(.success(Data([2])))
        }
        XCTAssertEqual(value, Data([1]))
    }
    func testFailureIsForwarded() async {
        do { _ = try await DataReply.wait { $0(.failure(BackendError.watchUnavailable)) }; XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .watchUnavailable) }
    }
    func testMissingCallbackTimesOutAndLateResponseIsIgnored() async {
        var callback: (@Sendable (Result<Data, Error>) -> Void)?
        do {
            _ = try await DataReply.wait(timeout: .milliseconds(5)) { callback = $0 }
            XCTFail()
        } catch { XCTAssertEqual(error as? BackendError, .watchUnavailable) }
        callback?(.success(Data([1])))
        callback?(.failure(BackendError.network))
    }
    func testCancelledBeforeStartDoesNotSend() async {
        var started = false
        let work = Task { try await DataReply.wait { complete in started = true; complete(.success(Data())) } }
        work.cancel()
        do { _ = try await work.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(started)
    }
    func testCancellationReleasesWaitAndLateCallbacksAreHarmless() async {
        let entered = expectation(description: "Request entered")
        var callback: (@Sendable (Result<Data, Error>) -> Void)?
        let work = Task { try await DataReply.wait(timeout: .seconds(10)) { callback = $0; entered.fulfill() } }
        await fulfillment(of: [entered], timeout: 2)
        work.cancel()
        do { _ = try await work.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        callback?(.success(Data([1])))
        callback?(.failure(BackendError.network))
    }
    func testTimeoutDoesNotRetryTheRequest() async {
        var starts = 0
        do { _ = try await DataReply.wait(timeout: .milliseconds(5)) { _ in starts += 1 }; XCTFail() }
        catch { XCTAssertEqual(error as? BackendError, .watchUnavailable) }
        XCTAssertEqual(starts, 1)
    }
}
