import Foundation

// MARK: - Model

struct Photo: Decodable, Identifiable {
    let id: Int
    let albumId: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - Error

enum NetworkError: LocalizedError, Equatable {
    case invalidResponse(statusCode: Int)
    case requestFailed(URLError.Code)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return "Server returned HTTP \(code)"
        case .requestFailed(let code):   return "Request failed: \(code)"
        case .decodingFailed:            return "Failed to decode server response"
        }
    }
}

// MARK: - Protocol

protocol NetworkServiceProtocol {
    func fetchPhotos() async throws -> [Photo]
}

// MARK: - Implementation

final class NetworkService: NetworkServiceProtocol {

    static let photosURL = URL(string: "https://jsonplaceholder.typicode.com/photos")!

    private let session: URLSession

    init(session: URLSession = NetworkService.makeFreshSession()) {
        self.session = session
    }

    func fetchPhotos() async throws -> [Photo] {
        do {
            let (data, response) = try await session.data(from: Self.photosURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode) else {
                throw NetworkError.invalidResponse(statusCode: statusCode)
            }
            return try JSONDecoder().decode([Photo].self, from: data)
        } catch let error as NetworkError {
            throw error
        } catch let urlError as URLError {
            throw NetworkError.requestFailed(urlError.code)
        } catch is DecodingError {
            throw NetworkError.decodingFailed
        }
        // Unexpected errors propagate as-is — nothing silently swallowed
    }

    private static func makeFreshSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }
}
