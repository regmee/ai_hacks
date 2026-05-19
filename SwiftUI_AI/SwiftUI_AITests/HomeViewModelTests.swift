import Foundation
import Testing
@testable import SwiftUI_AI

// MARK: - Mock

final class MockNetworkService: NetworkServiceProtocol, @unchecked Sendable {

    var pages: [[Photo]] = []
    var thrownError: Error?
    private(set) var requestedPages: [(page: Int, pageSize: Int)] = []

    func fetchPhotos(page: Int, pageSize: Int) async throws -> [Photo] {
        requestedPages.append((page, pageSize))
        if let thrownError {
            throw thrownError
        }
        guard page < pages.count else { return [] }
        return pages[page]
    }
}

// MARK: - Fixtures

private extension Photo {
    static func sample(id: Int) -> Photo {
        Photo(
            id: id,
            albumId: 1,
            title: "Photo \(id)",
            url: "https://example.com/\(id).jpg",
            thumbnailUrl: "https://example.com/t\(id).jpg"
        )
    }
}

@MainActor
private func makeViewModel(
    pages: [[Photo]] = [],
    error: Error? = nil,
    pageSize: Int = 2
) -> (HomeViewModel, MockNetworkService) {
    let mock = MockNetworkService()
    mock.pages = pages
    mock.thrownError = error
    let viewModel = HomeViewModel(networkService: mock, pageSize: pageSize)
    return (viewModel, mock)
}

// MARK: - Tests

@MainActor
struct HomeViewModelTests {

    @Test func loadInitialPopulatesPhotos() async {
        let page = [Photo.sample(id: 1), Photo.sample(id: 2)]
        let (viewModel, mock) = makeViewModel(pages: [page])

        await viewModel.loadInitial()

        #expect(viewModel.photos == page)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.canLoadMore == true)
        #expect(mock.requestedPages.count == 1)
        #expect(mock.requestedPages[0].page == 0)
        #expect(mock.requestedPages[0].pageSize == 2)
    }

    @Test func loadInitialSetsCanLoadMoreFalseWhenPageIsShort() async {
        let (viewModel, _) = makeViewModel(pages: [[Photo.sample(id: 1)]])

        await viewModel.loadInitial()

        #expect(viewModel.photos.count == 1)
        #expect(viewModel.canLoadMore == false)
    }

    @Test func loadInitialSurfacesNetworkError() async {
        let (viewModel, _) = makeViewModel(
            error: NetworkError.invalidResponse(statusCode: 500)
        )

        await viewModel.loadInitial()

        #expect(viewModel.photos.isEmpty)
        #expect(viewModel.errorMessage == NetworkError.invalidResponse(statusCode: 500).localizedDescription)
    }

    @Test func loadMoreAppendsNextPage() async {
        let firstPage = [Photo.sample(id: 1), Photo.sample(id: 2)]
        let secondPage = [Photo.sample(id: 3)]
        let (viewModel, mock) = makeViewModel(pages: [firstPage, secondPage])

        await viewModel.loadInitial()
        await viewModel.loadMoreIfNeeded(currentItem: firstPage.last)

        #expect(viewModel.photos.count == 3)
        #expect(viewModel.photos.last?.id == 3)
        #expect(viewModel.canLoadMore == false)
        #expect(mock.requestedPages.count == 2)
        #expect(mock.requestedPages[1].page == 1)
    }

    @Test func loadMoreDoesNothingWhenNotAtLastItem() async {
        let firstPage = [Photo.sample(id: 1), Photo.sample(id: 2)]
        let (viewModel, mock) = makeViewModel(pages: [firstPage, [Photo.sample(id: 3)]])

        await viewModel.loadInitial()
        await viewModel.loadMoreIfNeeded(currentItem: firstPage.first)

        #expect(viewModel.photos.count == 2)
        #expect(mock.requestedPages.count == 1)
        #expect(mock.requestedPages[0].page == 0)
        #expect(mock.requestedPages[0].pageSize == 2)
    }

    @Test func loadMoreSurfacesErrorWithoutClearingPhotos() async {
        let firstPage = [Photo.sample(id: 1), Photo.sample(id: 2)]
        let (viewModel, mock) = makeViewModel(pages: [firstPage, [Photo.sample(id: 3)]])

        await viewModel.loadInitial()
        mock.thrownError = NetworkError.decodingFailed
        await viewModel.loadMoreIfNeeded(currentItem: firstPage.last)

        #expect(viewModel.photos == firstPage)
        #expect(viewModel.errorMessage == NetworkError.decodingFailed.localizedDescription)
    }

    @Test func retryReloadsAfterInitialFailure() async {
        let (viewModel, mock) = makeViewModel(error: NetworkError.decodingFailed)

        await viewModel.loadInitial()
        #expect(viewModel.photos.isEmpty)

        mock.thrownError = nil
        mock.pages = [[Photo.sample(id: 1), Photo.sample(id: 2)]]
        await viewModel.retry()

        #expect(viewModel.photos.count == 2)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func dismissErrorClearsMessage() async {
        let (viewModel, _) = makeViewModel(error: NetworkError.decodingFailed)

        await viewModel.loadInitial()
        viewModel.dismissError()

        #expect(viewModel.errorMessage == nil)
    }
}
