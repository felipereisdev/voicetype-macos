import XCTest
@testable import VoiceType
import Core

final class GeneralSectionViewModelTests: XCTestCase {

    @MainActor
    func testTestKeyOk() async throws {
        let fake = FakeKeyTester()
        fake.result = TestKeyResult(ok: true, status: nil)
        let vm = GeneralSectionViewModel(groq: fake)
        await vm.testKey("gsk_ok")
        XCTAssertEqual(vm.testState, .ok)
    }

    @MainActor
    func testTestKeyInvalidShowsStatus() async throws {
        let fake = FakeKeyTester()
        fake.result = TestKeyResult(ok: false, status: 401)
        let vm = GeneralSectionViewModel(groq: fake)
        await vm.testKey("gsk_bad")
        XCTAssertEqual(vm.testState, .invalid(401))
    }

    @MainActor
    func testTestKeyNoResponse() async throws {
        let fake = FakeKeyTester()
        fake.result = TestKeyResult(ok: false, status: nil)
        let vm = GeneralSectionViewModel(groq: fake)
        await vm.testKey("gsk_x")
        XCTAssertEqual(vm.testState, .noResponse)
    }
}
