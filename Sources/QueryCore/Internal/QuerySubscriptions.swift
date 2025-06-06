// MARK: - QueryStoreSubscriptions

package final class QuerySubscriptions<QueryHandler: Sendable>: Sendable {
  private typealias Handler = (isTemporary: Bool, handler: QueryHandler)
  private typealias State = (currentId: Int, handlers: [Int: Handler])

  private let state = Lock<State>((currentId: 0, handlers: [:]))

  package init() {}
}

// MARK: - Count

extension QuerySubscriptions {
  package var count: Int {
    self.state.withLock { self.handlersCount(in: $0) }
  }

  private func handlersCount(in state: State) -> Int {
    state.handlers.count { !$0.value.isTemporary }
  }
}

// MARK: - Subscribing

extension QuerySubscriptions {
  package func add(
    handler: QueryHandler,
    isTemporary: Bool = false
  ) -> (subscription: QuerySubscription, isFirst: Bool) {
    self.state.withLock { state in
      let id = state.currentId
      defer { state.currentId += 1 }
      state.handlers[id] = (isTemporary, handler)
      let subscription = QuerySubscription { [weak self] in
        _ = self?.state.withLock { $0.handlers.removeValue(forKey: id) }
      }
      return (subscription, self.handlersCount(in: state) == 1)
    }
  }
}

// MARK: - ForEach

extension QuerySubscriptions {
  package func forEach(
    _ body: (QueryHandler) throws -> Void
  ) rethrows {
    try self.state.withLock { state in
      try state.handlers.forEach { try body($0.value.handler) }
    }
  }
}
