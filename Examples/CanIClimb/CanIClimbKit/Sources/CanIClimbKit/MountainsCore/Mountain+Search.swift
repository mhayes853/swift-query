import Dependencies
import SharingQuery

// MARK: - Search

extension Mountain {
  public enum Search: Hashable, Sendable {
    case recommended
    case text(String)
    case planned
  }
}

extension Mountain.Search {
  public init(text: String) {
    if text.isEmpty {
      self = .recommended
    } else {
      self = .text(text)
    }
  }
}

// MARK: - Searcher

extension Mountain {
  public struct SearchResult: Hashable, Sendable, Codable {
    public let mountains: IdentifiedArrayOf<Mountain>
    public let hasNextPage: Bool

    public init(mountains: IdentifiedArrayOf<Mountain>, hasNextPage: Bool) {
      self.mountains = mountains
      self.hasNextPage = hasNextPage
    }
  }

  public struct SearchRequest: Hashable, Sendable {
    public var search: Search
    public var page: Int

    public init(search: Mountain.Search, page: Int) {
      self.search = search
      self.page = page
    }
  }

  public protocol Searcher: Sendable {
    func searchMountains(by request: SearchRequest) async throws -> SearchResult
  }

  public enum SearcherKey: DependencyKey {
    public static let liveValue: any Mountain.Searcher = CanIClimbAPI.shared
  }
}

extension Mountain {
  @MainActor
  public final class MockSearcher: Searcher {
    public var results = [Int: Result<Mountain.SearchResult, any Error>]()

    public init() {}

    public func searchMountains(
      by request: SearchRequest
    ) async throws -> Mountain.SearchResult {
      guard let result = self.results[request.page] else { throw NoResultError() }
      return try result.get()
    }

    private struct NoResultError: Error {}
  }
}

extension CanIClimbAPI: Mountain.Searcher {}

// MARK: - Query

extension Mountain {
  public static func searchQuery(_ search: Search) -> some InfiniteQueryRequest<Int, SearchResult> {
    SearchQuery(search: search)
  }

  public struct SearchQuery: InfiniteQueryRequest, Hashable {
    public typealias PageValue = Mountain.SearchResult
    public typealias PageID = Int

    let search: Search

    public let initialPageId = 0

    public func pageId(
      after page: InfiniteQueryPage<PageID, PageValue>,
      using paging: InfiniteQueryPaging<PageID, PageValue>,
      in context: QueryContext
    ) -> PageID? {
      page.value.hasNextPage ? page.id + 1 : nil
    }

    public func fetchPage(
      using paging: InfiniteQueryPaging<PageID, PageValue>,
      in context: QueryContext,
      with continuation: QueryContinuation<PageValue>
    ) async throws -> PageValue {
      @Dependency(Mountain.SearcherKey.self) var searcher
      @Dependency(\.defaultQueryClient) var client
      @Dependency(\.defaultDatabase) var database

      do {
        let request = Mountain.SearchRequest(search: self.search, page: paging.pageId)
        let searchResult = try await searcher.searchMountains(by: request)
        client.updateDetailQueries(mountains: searchResult.mountains)
        try await database.write { try Mountain.save(searchResult.mountains, in: $0) }
        return searchResult
      } catch {
        guard paging.pageId == self.initialPageId && context.isLastRetryAttempt else { throw error }
        let mountains = try await database.read { db in
          try Mountain.findAll(matching: self.search, in: db)
        }
        let searchResult = Mountain.SearchResult(
          mountains: IdentifiedArray(uniqueElements: mountains),
          hasNextPage: false
        )
        continuation.yield(searchResult, using: context)
        throw error
      }
    }
  }
}

extension QueryClient {
  fileprivate func updateDetailQueries(mountains: IdentifiedArrayOf<Mountain>) {
    self.withStores(matching: .mountain, of: Mountain.Query.State.self) { stores, createStore in
      for mountain in mountains {
        if let store = stores[.mountain(with: mountain.id)] {
          store.currentValue = mountain
        } else {
          stores.update(createStore(for: Mountain.query(id: mountain.id), initialValue: mountain))
        }
      }
    }
  }
}
