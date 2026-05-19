//
//  HomeView.swift
//  SwiftUI_AI
//
//  Created by AR on 2026-05-18.
//  Copyright © 2026. All rights reserved.
//

import Observation
import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
final class HomeViewModel {

    private(set) var photos: [Photo] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = true
    private(set) var errorMessage: String?

    private let networkService: any NetworkServiceProtocol
    private let pageSize: Int
    private var nextPage = 0

    init(networkService: any NetworkServiceProtocol, pageSize: Int = 20) {
        self.networkService = networkService
        self.pageSize = pageSize
    }

    static func live(pageSize: Int = 20) -> HomeViewModel {
        HomeViewModel(networkService: NetworkService(), pageSize: pageSize)
    }

    func loadInitial() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        nextPage = 0
        canLoadMore = true
        photos = []

        defer { isLoading = false }

        do {
            let page = try await networkService.fetchPhotos(page: nextPage, pageSize: pageSize)
            photos = page
            nextPage += 1
            canLoadMore = page.count == pageSize
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadMoreIfNeeded(currentItem: Photo?) async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard let currentItem, currentItem.id == photos.last?.id else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await networkService.fetchPhotos(page: nextPage, pageSize: pageSize)
            photos.append(contentsOf: page)
            nextPage += 1
            canLoadMore = page.count == pageSize
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func retry() async {
        if photos.isEmpty {
            await loadInitial()
        } else {
            await loadMoreIfNeeded(currentItem: photos.last)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private static func message(for error: Error) -> String {
        if let networkError = error as? NetworkError {
            return networkError.localizedDescription
        }
        return error.localizedDescription
    }
}

// MARK: - View

struct HomeView: View {
    @State private var viewModel = HomeViewModel.live()

    var body: some View {
        Group {
            if let errorMessage = viewModel.errorMessage, viewModel.photos.isEmpty {
                ContentUnavailableView {
                    Label("Unable to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.retry() }
                    }
                }
            } else {
                List(viewModel.photos) { photo in
                    Text(photo.title)
                        .task {
                            await viewModel.loadMoreIfNeeded(currentItem: photo)
                        }
                }
                .overlay {
                    if viewModel.isLoading {
                        ProgressView()
                    }
                }
            }
        }
        .navigationTitle("Photos")
        .safeAreaInset(edge: .bottom) {
            if let errorMessage = viewModel.errorMessage, !viewModel.photos.isEmpty {
                HStack {
                    Text(errorMessage)
                        .font(.footnote)
                    Spacer()
                    Button("Retry") {
                        Task { await viewModel.retry() }
                    }
                    .font(.footnote)
                }
                .padding()
                .background(.bar)
            } else if viewModel.isLoadingMore {
                ProgressView()
                    .padding()
            }
        }
        .task {
            await viewModel.loadInitial()
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
