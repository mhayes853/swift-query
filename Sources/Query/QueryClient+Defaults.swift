import IssueReporting
import QueryCore

#if SwiftQueryWebBrowser
  import QueryBrowser
#endif

// MARK: - Default Init

extension QueryClient {
  /// Creates a client.
  ///
  /// - Parameters:
  ///   - defaultContext: The default ``QueryContext`` to use for each ``QueryStore`` created by the client.
  ///   - storeCache: The ``StoreCache`` to use.
  public convenience init(
    defaultContext: QueryContext = QueryContext(),
    storeCache: sending some StoreCache = DefaultStoreCache()
  ) {
    self.init(
      defaultContext: defaultContext,
      storeCache: storeCache,
      storeCreator: isTesting ? .defaultTesting : .default()
    )
  }
}

// MARK: - DefaultStoreCreator

extension QueryClient {
  /// The default `StoreCreator` used by a query client.
  ///
  /// This store creator applies a set of default modifiers to both `QueryRequest` and
  /// `MutationRequest` instances.
  ///
  /// **Queries**
  /// - Deduplication
  /// - Retries
  /// - Automatic Fetching
  /// - Refetching when the network comes back online
  /// - Refetching when the app reenters from the background
  ///
  /// **Mutations**
  /// - Retries
  public struct DefaultStoreCreator: StoreCreator {
    let retryLimit: Int
    let backoff: QueryBackoffFunction?
    let delayer: (any QueryDelayer)?
    let queryEnableAutomaticFetchingCondition: any FetchCondition
    let networkObserver: (any NetworkObserver)?
    let activityObserver: (any ApplicationActivityObserver)?

    public func store<Query: QueryRequest>(
      for query: Query,
      in context: QueryContext,
      with initialState: Query.State
    ) -> QueryStore<Query.State> {
      let backoff = self.backoff ?? context.queryBackoffFunction
      let delayer = AnyDelayer(self.delayer ?? context.queryDelayer)
      if query is any MutationRequest {
        return .detached(
          query: query.retry(limit: self.retryLimit)
            .backoff(backoff)
            .delayer(delayer),
          initialState: initialState,
          initialContext: context
        )
      }
      return .detached(
        query:
          query.retry(limit: self.retryLimit)
          .backoff(backoff)
          .delayer(delayer)
          .enableAutomaticFetching(
            onlyWhen: AnyFetchCondition(self.queryEnableAutomaticFetchingCondition)
          )
          .refetchOnChange(of: self.refetchOnChangeCondition)
          .deduplicated(),
        initialState: initialState,
        initialContext: context
      )
    }

    private var refetchOnChangeCondition: AnyFetchCondition {
      switch (self.networkObserver, self.activityObserver) {
      case (let networkObserver?, let activityObserver?):
        return AnyFetchCondition(
          .connected(to: networkObserver) && .applicationIsActive(observer: activityObserver)
        )
      case (let networkObserver?, _):
        return AnyFetchCondition(.connected(to: networkObserver))
      case (_, let activityObserver?):
        return AnyFetchCondition(.applicationIsActive(observer: activityObserver))
      default:
        return AnyFetchCondition(.always(false))
      }
    }
  }
}

extension QueryClient.StoreCreator where Self == QueryClient.DefaultStoreCreator {
  /// The default `StoreCreator` used by a query client for testing.
  ///
  /// In testing, retries are disabled, and the network status and application activity status are
  /// not observed, delays are disabled, and the backoff function is `QueryBackoffFunction.noBackoff`.
  public static var defaultTesting: Self {
    .default(
      retryLimit: 0,
      backoff: .noBackoff,
      delayer: .noDelay,
      queryEnableAutomaticFetchingCondition: .always(true),
      networkObserver: nil,
      activityObserver: nil
    )
  }

  /// The default `StoreCreator` used by a query client.
  ///
  /// This store creator applies a set of default modifiers to both `QueryRequest` and
  /// `MutationRequest` instances.
  ///
  /// **Queries**
  /// - Deduplication
  /// - Retries
  /// - Automatic Fetching
  /// - Refetching when the network comes back online
  /// - Refetching when the app reenters from the background
  ///
  /// **Mutations**
  /// - Retries
  ///
  /// - Parameters:
  ///   - retryLimit: The maximum number of retries for queries and mutations.
  ///   - backoff: The backoff function to use for retries.
  ///   - delayer: The `QueryDelayer` to use for delaying the execution of a retry.
  ///   - queryEnableAutomaticFetchingCondition: The default `FetchCondition` that determines
  ///   whether or not automatic fetching is enabled for queries (and not mutations).
  ///   - networkObserver: The default `NetworkObserver` to use.
  ///   - activityObserver: The default `ApplicationActivityObserver` to use.
  /// - Returns: A ``QueryCore/QueryClient/DefaultStoreCreator``.
  public static func `default`(
    retryLimit: Int = 3,
    backoff: QueryBackoffFunction? = nil,
    delayer: (any QueryDelayer)? = nil,
    queryEnableAutomaticFetchingCondition: any FetchCondition = .always(true),
    networkObserver: (any NetworkObserver)? = QueryClient.defaultNetworkObserver,
    activityObserver: (any ApplicationActivityObserver)? = QueryClient
      .defaultApplicationActivityObserver
  ) -> Self {
    Self(
      retryLimit: retryLimit,
      backoff: backoff,
      delayer: delayer,
      queryEnableAutomaticFetchingCondition: queryEnableAutomaticFetchingCondition,
      networkObserver: networkObserver,
      activityObserver: activityObserver
    )
  }
}

// MARK: - Defaults

extension QueryClient {
  /// The default ``NetworkObserver`` to use for observing the user's connection status.
  ///
  /// - On Darwin platforms, `NWPathMonitorObserver` is used.
  /// - On Broswer platforms (WASI), `NavigatorOnlineObserver` is used.
  /// - On other platforms, the value is nil.
  public static var defaultNetworkObserver: (any NetworkObserver)? {
    #if canImport(Network)
      NWPathMonitorObserver.startingShared()
    #elseif SwiftQueryWebBrowser && canImport(JavaScriptKit)
      NavigatorOnlineObserver.shared
    #else
      nil
    #endif
  }

  /// The default ``ApplicationActivityObserver`` to use for detetcing whether or not the app is active.
  ///
  /// - On Darwin platforms, the underlying `XXXApplication` class is used.
  /// - On Broswer platforms (WASI), the `WindowVisibilityObserver` is used.
  /// - On other platforms, the value is nil.
  public static var defaultApplicationActivityObserver: (any ApplicationActivityObserver)? {
    #if os(iOS) || os(tvOS) || os(visionOS)
      UIApplicationActivityObserver.shared
    #elseif os(macOS)
      NSApplicationActivityObserver.shared
    #elseif os(watchOS)
      if #available(watchOS 7.0, *) {
        WKApplicationActivityObserver.shared
      } else {
        nil
      }
    #elseif SwiftQueryWebBrowser && canImport(JavaScriptKit)
      WindowVisibilityObserver.shared
    #else
      nil
    #endif
  }
}
