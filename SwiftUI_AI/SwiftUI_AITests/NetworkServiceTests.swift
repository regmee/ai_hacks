import Testing
import Foundation
@testable import SwiftUI_AI

// MARK: - Mock URLProtocol
// Intercepts URLSession requests so tests never hit the network.

final class MockURLProtocol: URLProtocol {

    // nonisolated(unsafe): readable from background URLSession threads despite @MainActor default isolation.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }

    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    nonisolated override func stopLoading() {}
}

// MARK: - Fixtures

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: NetworkService.photosURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private let validPhotoJSON = Data("""
[{"id":1,"albumId":1,"title":"sample photo","url":"https://example.com/1.jpg","thumbnailUrl":"https://example.com/t1.jpg"}]
""".utf8)

private let emptyArrayJSON  = Data("[]".utf8)
private let malformedJSON   = Data("not json at all".utf8)
private let emptyData       = Data()

// MARK: - Tests

// .serialized prevents concurrent tests from overwriting the shared static requestHandler
@Suite(.serialized)
@MainActor
struct NetworkServiceTests {

    // Happy path: valid JSON decodes into a [Photo] array.
    @Test func fetchPhotosReturnsDecodedPhotos() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 200), validPhotoJSON) }
        let photos = try await NetworkService(session: makeMockSession()).fetchPhotos(page: 0, pageSize: 20)
        #expect(photos.count == 1)
        #expect(photos[0].id == 1)
        #expect(photos[0].albumId == 1)
        #expect(photos[0].title == "sample photo")
        #expect(photos[0].url == "https://example.com/1.jpg")
        #expect(photos[0].thumbnailUrl == "https://example.com/t1.jpg")
    }

    // A 200 response with an empty array is valid — returns [] without throwing.
    @Test func fetchPhotosEmptyArray() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 200), emptyArrayJSON) }
        let photos = try await NetworkService(session: makeMockSession()).fetchPhotos(page: 0, pageSize: 20)
        #expect(photos.isEmpty)
    }

    // HTTP 500 must throw NetworkError.invalidResponse(statusCode: 500).
    @Test func fetchPhotosThrowsOnHTTP500() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 500), Data()) }
        await #expect(throws: NetworkError.invalidResponse(statusCode: 500)) {
            try await NetworkService(session: makeMockSession()).fetchPhotos(page: 0, pageSize: 20)
        }
    }

    // HTTP 404 must throw NetworkError.invalidResponse(statusCode: 404).
    @Test func fetchPhotosThrowsOnHTTP404() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 404), Data()) }
        await #expect(throws: NetworkError.invalidResponse(statusCode: 404)) {
            try await NetworkService(session: makeMockSession()).fetchPhotos(page: 0, pageSize: 20)
        }
    }

    // A transport-layer failure is wrapped into NetworkError.requestFailed.
    @Test func fetchPhotosThrowsOnNetworkFailure() async throws {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: NetworkError.requestFailed(.notConnectedToInternet)) {
            try await NetworkService(session: makeMockSession()).fetchPhotos(page: 0, pageSize: 20)
        }
    }

    // Corrupt bytes from the server are wrapped into NetworkError.decodingFailed.
    @Test func fetchPhotosThrowsOnMalformedJSON() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 200), malformedJSON) }
        await #expect(throws: NetworkError.decodingFailed) {
            try await NetworkService(session: makeMockSession()).fetchPhotos(page: 0, pageSize: 20)
        }
    }

    // Zero bytes from the server are also wrapped into NetworkError.decodingFailed.
    @Test func fetchPhotosThrowsOnEmptyData() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 200), emptyData) }
        await #expect(throws: NetworkError.decodingFailed) {
            try await NetworkService(session: makeMockSession()).fetchPhotos(page: 0, pageSize: 20)
        }
    }
}
