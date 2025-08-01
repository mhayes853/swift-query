import Foundation

// MARK: - OpaqueQueryState

/// An untyped state type that type erases any ``QueryStateProtocol`` conformance.
///
/// Generally, you only access this type from an ``OpaqueQueryStore``, which is typically accessed
/// via pattern matching on a ``QueryClient``. See <doc:PatternMatchingAndStateManagement> for more.
public struct OpaqueQueryState {
  /// The underlying base state.
  public private(set) var base: any QueryStateProtocol

  /// Creates an opaque state.
  ///
  /// - Parameter base: The base state to erase.
  public init(_ base: any QueryStateProtocol) {
    self.base = base
  }
}

// MARK: - QueryStateProtocol

extension OpaqueQueryState: QueryStateProtocol {
  public typealias StateValue = (any Sendable)?
  public typealias QueryValue = any Sendable
  public typealias StatusValue = any Sendable

  public var currentValue: StateValue { self.base.currentValue }
  public var initialValue: StateValue { self.base.initialValue }
  public var valueUpdateCount: Int { self.base.valueUpdateCount }
  public var valueLastUpdatedAt: Date? { self.base.valueLastUpdatedAt }
  public var isLoading: Bool { self.base.isLoading }
  public var error: (any Error)? { self.base.error }
  public var errorUpdateCount: Int { self.base.errorUpdateCount }
  public var errorLastUpdatedAt: Date? { self.base.errorLastUpdatedAt }

  public mutating func scheduleFetchTask(
    _ task: inout QueryTask<any Sendable>
  ) {
    func open<State: QueryStateProtocol>(state: inout State) {
      var inner = task.map { $0 as! State.QueryValue }
      state.scheduleFetchTask(&inner)
      task = inner.map { $0 as any Sendable }
    }
    open(state: &self.base)
  }

  public mutating func reset(using context: QueryContext) -> ResetEffect {
    func open<State: QueryStateProtocol>(state: inout State) -> ResetEffect {
      ResetEffect(tasksCancellable: state.reset(using: context).tasksCancellable)
    }
    return open(state: &self.base)
  }

  public mutating func update(
    with result: Result<any Sendable, any Error>,
    for task: QueryTask<any Sendable>
  ) {
    func open<State: QueryStateProtocol>(state: inout State) {
      state.update(
        with: result.map { $0 as! State.QueryValue },
        for: task.map { $0 as! State.QueryValue }
      )
    }
    open(state: &self.base)
  }

  public mutating func update(
    with result: Result<(any Sendable)?, any Error>,
    using context: QueryContext
  ) {
    func open<State: QueryStateProtocol>(state: inout State) {
      state.update(with: result.map { $0 as! State.StateValue }, using: context)
    }
    open(state: &self.base)
  }

  public mutating func finishFetchTask(_ task: QueryTask<any Sendable>) {
    func open<State: QueryStateProtocol>(state: inout State) {
      state.finishFetchTask(task.map { $0 as! State.QueryValue })
    }
    open(state: &self.base)
  }
}
