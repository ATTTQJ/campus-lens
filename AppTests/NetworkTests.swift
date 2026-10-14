import XCTest
import Foundation
@testable import CampusLens
import CampusLensCore

/// Test-only URL protocol. No real network or credentials are used.
final class VisionStubProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.global().asyncAfter(deadline:.now()+0.3) { [self] in
            lock.lock(); let isStopped = self.stopped; lock.unlock()
            guard !isStopped else { return }
            if request.url?.path == "/timeout" { client?.urlProtocol(self,didFailWithError:URLError(.timedOut)); return }
            let content = #"{"scene":"award","subjectID":0,"explanation":"本机候选主体适合颁奖场景"}"#
            let data = try! JSONSerialization.data(withJSONObject:["choices":[["message":["content":content]]]])
            let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}
@MainActor
final class NetworkTests: XCTestCase {
    func makeClient() -> AIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [VisionStubProtocol.self]
        return AIClient(session:URLSession(configuration:config))
    }
    func testVisionEnvelopeAndTimeout() async throws {
        let client = makeClient(), sample = Fixture.sample(id:UUID())
        let config = AIConfiguration(enabled:true,endpoint:"https://fixture.invalid/success",model:"test-only",key:"test-only-placeholder")
        let result = try await client.suggest(sample:sample,configuration:config)
        XCTAssertEqual(result.scene,.award)
        do {
            _ = try await client.suggest(sample:sample,configuration:AIConfiguration(enabled:true,endpoint:"https://fixture.invalid/timeout",model:"test-only",key:"test-only-placeholder"))
            XCTFail("Timeout should fail")
        } catch { XCTAssertEqual((error as? URLError)?.code,.timedOut) }
    }
    func testLateResponseCannotCoverNewResult() async throws {
        let model = AppModel(aiClient:makeClient())
        model.sample = Fixture.sample(id:UUID()); model.confirmed = true
        // The test-only key is stored then removed; no external API request occurs.
        let originalKey = try KeychainStore.read()
        defer { try? KeychainStore.write(originalKey) }
        try KeychainStore.write("test-only-placeholder")
        model.endpoint = "https://fixture.invalid/success"; model.modelName = "test-only"; model.aiEnabled = true
        model.requestAI()
        try await Task.sleep(for:.milliseconds(100))
        try model.clearCurrent()
        let latest = Fixture.sample(id:UUID()); model.sample = latest
        try await Task.sleep(for:.milliseconds(600))
        XCTAssertEqual(model.sample?.id,latest.id); XCTAssertNil(model.suggestion); XCTAssertTrue(model.aiStatus.isEmpty)
    }
}
