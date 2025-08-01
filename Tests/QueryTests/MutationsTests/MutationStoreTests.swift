import CustomDump
import Foundation
@_spi(Warnings) import Query
import QueryTestHelpers
import Testing

@Suite("MutationStore tests")
struct MutationStoreTests {
  private let client = QueryClient()

  @Test("Mutate Returns Mutated Value")
  func mutate() async throws {
    let mutation = EmptyMutation()
    let store = self.client.store(for: mutation)
    let result = try await store.mutate(with: "blob")
    expectNoDifference(result, "blob")
    expectNoDifference(store.currentValue, "blob")
  }

  @Test("Mutate Adds Value To History")
  func mutateAddsValueToHistory() async throws {
    let mutation = EmptyMutation()
    let store = self.client.store(for: mutation)
    try await store.mutate(with: "blob")
    expectNoDifference(store.history.count, 1)
    expectNoDifference(store.history[0].arguments, "blob")
    expectNoDifference(store.history[0].status.isSuccessful, true)

    try await store.mutate(with: "blob jr")
    expectNoDifference(store.history.count, 2)
    expectNoDifference(store.history[1].arguments, "blob jr")
    expectNoDifference(store.history[1].status.isSuccessful, true)
  }

  @Test("Mutation Is Loading")
  func mutationIsLoading() async throws {
    let mutation = SleepingMutation()
    let store = self.client.store(for: mutation)
    mutation.didBeginSleeping = {
      expectNoDifference(store.isLoading, true)
    }
    try await store.mutate(with: "blob")
    expectNoDifference(store.isLoading, false)
  }

  @Test("Mutation Is Loading, Adds Loading Status To History")
  func mutationIsLoadingAddsLoadingStatusToHistory() async throws {
    let mutation = SleepingMutation()
    let store = self.client.store(for: mutation)
    mutation.didBeginSleeping = {
      expectNoDifference(store.history.count, 1)
      expectNoDifference(store.history[0].status.isLoading, true)
      expectNoDifference(store.history[0].arguments, "blob")
    }
    try await store.mutate(with: "blob")
  }

  @Test("Mutation Throws Error")
  func mutationThrowsError() async throws {
    let mutation = FailableMutation()
    let store = self.client.store(for: mutation)
    let result = try? await store.mutate(with: "blob")
    expectNoDifference(store.error != nil, true)
    expectNoDifference(result, nil)
  }

  @Test("Mutation Throws Error, Adds Error Status To History")
  func mutationThrowsErrorAddsErrorStatusToHistory() async throws {
    let mutation = FailableMutation()
    let store = self.client.store(for: mutation)
    _ = try? await store.mutate(with: "blob")
    expectNoDifference(store.history.count, 1)
    expectNoDifference(store.history[0].status.isFailure, true)
    expectNoDifference(store.history[0].arguments, "blob")
  }

  @Test("Can Wait For Individual Historical Mutation")
  func canWaitForIndividualHistoricalMutation() async throws {
    let mutation = WaitableMutation()
    mutation.state.withLock { $0.willWait = true }
    let store = self.client.store(for: mutation)

    let handle = RecursiveLock<QueryTask<String>?>(nil)
    mutation.onLoading(for: "blob") {
      handle.withLock { $0 = store.history[0].task }
    }
    Task { try await store.mutate(with: "blob") }
    try await mutation.waitForLoading(on: "blob")

    mutation.state.withLock { $0.willWait = false }
    _ = try? await store.mutate(with: "blob jr")
    expectNoDifference(store.history.map(\.status.isLoading), [true, false])

    let task = try #require(handle.withLock { $0 })
    async let value = task.runIfNeeded()
    await mutation.advance(on: "blob")
    _ = try await value
    expectNoDifference(store.history.map(\.status.isLoading), [false, false])
  }

  @Test("Mutation History Finished Date After Start Date")
  func mutationHistoryFinishedDateAfterStartDate() async throws {
    let mutation = WaitableMutation()

    let store = self.client.store(for: mutation)
    mutation.onLoading(for: "blob") {
      expectNoDifference(store.history[0].lastUpdatedAt, nil)
    }
    _ = try? await store.mutate(with: "blob")
    let endDate = try #require(store.history[0].lastUpdatedAt)
    expectNoDifference(endDate > store.history[0].startDate, true)
  }

  @Test("State Values Based On Most Recent Mutation")
  func stateValuesBasedOnMostRecentMutation() async throws {
    let mutation = WaitableMutation()
    mutation.state.withLock { $0.willWait = true }
    let store = self.client.store(for: mutation)

    mutation.onLoading(for: "blob") {
      expectNoDifference(store.isLoading, true)
      Task { try await store.mutate(with: "blob jr") }
    }
    mutation.onLoading(for: "blob jr") {
      expectNoDifference(store.isLoading, true)
      Task {
        await mutation.advance(on: "blob")
      }
    }
    try await store.mutate(with: "blob")
    expectNoDifference(store.isLoading, true)
    expectNoDifference(store.currentValue, nil)

    let task = store.history.first { $0.arguments == "blob jr" }?.task
    await mutation.advance(on: "blob jr")
    _ = try await task?.runIfNeeded()
    expectNoDifference(store.isLoading, false)
    expectNoDifference(store.currentValue, "blob jr")
  }

  @Test("Only Updates Value Update Count And Date When Current Mutation Is Completed")
  func onlyUpdatesValueUpdateCountAndDateWhenCurrentMutationIsCompleted() async throws {
    let mutation = WaitableMutation()
    mutation.state.withLock { $0.willWait = true }
    let updatedAtDate = Date()
    let store = self.client.store(for: mutation)
    store.context.queryClock = .timeFreeze(updatedAtDate)

    mutation.onLoading(for: "blob") {
      Task { try await store.mutate(with: "blob jr") }
    }
    mutation.onLoading(for: "blob jr") {
      Task {
        await mutation.advance(on: "blob")
      }
    }
    try await store.mutate(with: "blob")
    expectNoDifference(store.valueUpdateCount, 0)
    expectNoDifference(store.valueLastUpdatedAt, nil)

    let task = store.history.first { $0.arguments == "blob jr" }?.task
    await mutation.advance(on: "blob jr")
    _ = try await task?.runIfNeeded()
    expectNoDifference(store.valueUpdateCount, 1)
    expectNoDifference(store.valueLastUpdatedAt, updatedAtDate)
  }

  @Test("State Values Based On Most Recent Mutation, Throws Error")
  func stateValuesBasedOnMostRecentMutationThrowsError() async throws {
    struct SomeError: Error {}

    let mutation = WaitableMutation()
    mutation.state.withLock { $0.willWait = true }
    let store = self.client.store(for: mutation)

    mutation.onLoading(for: "blob") {
      expectNoDifference(store.isLoading, true)
      Task { try await store.mutate(with: "blob jr") }
    }
    mutation.onLoading(for: "blob jr") {
      expectNoDifference(store.isLoading, true)
      Task {
        await mutation.advance(on: "blob")
      }
    }
    try await store.mutate(with: "blob")
    expectNoDifference(store.isLoading, true)
    expectNoDifference(store.error == nil, true)

    let task = store.history.first { $0.arguments == "blob jr" }?.task
    await mutation.advance(on: "blob jr", with: SomeError())
    _ = try? await task?.runIfNeeded()
    expectNoDifference(store.isLoading, false)
    expectNoDifference(store.error != nil, true)
  }

  @Test("Only Updates Error Update Count And Date When Current Mutation Is Completed")
  func onlyUpdatesErrorUpdateCountAndDateWhenCurrentMutationIsCompleted() async throws {
    struct SomeError: Error {}

    let mutation = WaitableMutation()
    mutation.state.withLock { $0.willWait = true }
    let updatedAtDate = Date()
    let store = self.client.store(for: mutation)
    store.context.queryClock = .custom { updatedAtDate }

    mutation.onLoading(for: "blob") {
      Task { try await store.mutate(with: "blob jr") }
    }
    mutation.onLoading(for: "blob jr") {
      Task {
        await mutation.advance(on: "blob", with: SomeError())
      }
    }
    _ = try? await store.mutate(with: "blob")
    expectNoDifference(store.errorUpdateCount, 0)
    expectNoDifference(store.errorLastUpdatedAt, nil)

    let task = store.history.first { $0.arguments == "blob jr" }?.task
    await mutation.advance(on: "blob jr", with: SomeError())
    _ = try? await task?.runIfNeeded()
    expectNoDifference(store.errorUpdateCount, 1)
    expectNoDifference(store.errorLastUpdatedAt, updatedAtDate)
  }

  @Test("History Value Last Updated At Equals State Last Updated At")
  func historyValueLastUpdatedAtEqualsStateLastUpdatedAt() async throws {
    let store = self.client.store(for: EmptyMutation())
    try await store.mutate(with: "blob")
    expectNoDifference(store.history.first?.lastUpdatedAt, store.valueLastUpdatedAt)
  }

  @Test("History Error Last Updated At Equals State Last Updated At")
  func historyErrorLastUpdatedAtEqualsStateLastUpdatedAt() async throws {
    let mutation = FailableMutation()
    let store = self.client.store(for: mutation)
    _ = try? await store.mutate(with: "blob")
    expectNoDifference(store.history.first?.lastUpdatedAt, store.errorLastUpdatedAt)
  }

  @Test("Automatic Fetching Disabled By Default On Regular Store")
  func automaticFetchingDisabledByDefault() async throws {
    let mutation = FailableMutation()
    let store = QueryStore.detached(mutation: mutation)
    expectNoDifference(store.isAutomaticFetchingEnabled, false)
  }

  @Test("Reports Issue When Fetching Mutation Through A Base QueryStore With No History")
  func reportsIssueWhenFetchingMutationThroughABaseQueryStoreWithNoHistory() async throws {
    let mutation = FailableMutation()
    let store = QueryStore.detached(mutation: mutation)
    await withKnownIssue {
      _ = try? await store.fetch()
    } matching: {
      $0.comments.contains(.warning(.mutationWithNoArgumentsOrHistory))
    }
    expectNoDifference(store.history.isEmpty, true)
  }

  @Test("Retries Latest History When Calling Fetch On Base QueryStore For Mutation")
  func retriesLatestHistoryWhenCallingFetchOnBaseQueryStoreForMutation() async throws {
    let mutation = EmptyMutation()
    let store = QueryStore.detached(mutation: mutation)
    try await store.mutate(with: "blob")
    try await store.fetch()
    expectNoDifference(store.currentValue, "blob")
    expectNoDifference(store.history.count, 2)
    expectNoDifference(store.history.map(\.arguments), ["blob", "blob"])
  }

  @Test("Retries Latest History When Calling RetryLatest")
  func retriesLatestHistoryWhenCallingRetryLatest() async throws {
    let mutation = EmptyMutation()
    let store = QueryStore.detached(mutation: mutation)
    try await store.mutate(with: "blob")
    let value = try await store.retryLatest()
    expectNoDifference(value, "blob")
    expectNoDifference(store.history.count, 2)
    expectNoDifference(store.history.map(\.arguments), ["blob", "blob"])
  }

  @Test("Successful Mutation Events")
  func successfulMutationEvents() async throws {
    let store = self.client.store(for: EmptyMutation())
    let collector = MutationStoreEventsCollector<
      EmptyMutation.Arguments, EmptyMutation.ReturnValue
    >()
    try await store.mutate(with: "blob", handler: collector.eventHandler())

    collector.expectEventsMatch([
      .stateChanged,
      .mutatingStarted("blob"),
      .mutationResultReceived("blob", .success("blob")),
      .stateChanged,
      .mutatingEnded("blob")
    ])
  }

  @Test("Failing Mutation Events")
  func failingMutationEvents() async throws {
    let mutation = FailableMutation()
    let store = self.client.store(for: mutation)
    let collector = MutationStoreEventsCollector<
      FailableMutation.Arguments, FailableMutation.ReturnValue
    >()
    _ = try? await store.mutate(with: "blob", handler: collector.eventHandler())

    collector.expectEventsMatch([
      .stateChanged,
      .mutatingStarted("blob"),
      .mutationResultReceived("blob", .failure(FailableMutation.MutateError())),
      .stateChanged,
      .mutatingEnded("blob")
    ])
  }

  @Test("Subscribe To Mutation Events")
  func subscribeToMutationEvents() async throws {
    let mutation = EmptyMutation()
    let store = self.client.store(for: mutation)
    let collector = MutationStoreEventsCollector<
      EmptyMutation.Arguments, EmptyMutation.ReturnValue
    >()
    let subscription = try await store.subscribe(with: collector.eventHandler())
    try await store.mutate(with: "blob")

    collector.expectEventsMatch([
      .stateChanged,
      .stateChanged,
      .mutatingStarted("blob"),
      .mutationResultReceived("blob", .success("blob")),
      .stateChanged,
      .mutatingEnded("blob")
    ])
    subscription.cancel()
  }

  @Test("Default MutationStoreTask Name")
  func defaultMutationStoreTaskName() async throws {
    let store = self.client.store(for: EmptyMutation())
    let task = store.mutateTask(with: "blob")
    expectNoDifference(
      task.configuration.name,
      "QueryStore<MutationState<String, String>> Mutate Task"
    )
  }

  @Test("Default RetryLatest MutationStoreTask Name")
  func defaultRetryLatestMutationStoreTaskName() async throws {
    let store = self.client.store(for: EmptyMutation())
    try await store.mutate(with: "blob")
    let task = store.retryLatestTask()
    expectNoDifference(
      task.configuration.name,
      "QueryStore<MutationState<String, String>> Retry Latest Task"
    )
  }

  @Test("Uses More Recent State Update Between History And Yielding")
  func mutationStoreUsesMoreRecentStateUpdate() async throws {
    let controller = TestQueryController<EmptyMutation>()
    let store = self.client.store(for: EmptyMutation().controlled(by: controller))
    let clock = TestQueryClock(date: Date())
    store.context.queryClock = clock

    try await store.mutate(with: "blob")
    expectNoDifference(store.currentValue, "blob")
    expectNoDifference(store.valueLastUpdatedAt, clock.date)
    expectNoDifference(store.valueUpdateCount, 1)

    clock.date += 1000
    controller.controls.withLock { $0?.yield("test") }
    expectNoDifference(store.currentValue, "test")
    expectNoDifference(store.valueLastUpdatedAt, clock.date)
    expectNoDifference(store.valueUpdateCount, 2)

    clock.date += 1000
    try await store.mutate(with: "foo")
    expectNoDifference(store.currentValue, "foo")
    expectNoDifference(store.valueLastUpdatedAt, clock.date)
    expectNoDifference(store.valueUpdateCount, 3)
  }

  @Test("Uses More Recent Error Update Between History And Yielding")
  func mutationStoreUsesMoreRecentErrorUpdate() async throws {
    struct SomeError: Equatable, Error {}

    let controller = TestQueryController<EmptyMutation>()
    let mutation = FailableMutation()
    let store = self.client.store(for: mutation.controlled(by: controller))
    let clock = TestQueryClock(date: Date())
    store.context.queryClock = clock

    _ = try? await store.mutate(with: "blob")
    expectNoDifference(
      store.error as? FailableMutation.MutateError,
      FailableMutation.MutateError()
    )
    expectNoDifference(store.errorLastUpdatedAt, clock.date)
    expectNoDifference(store.errorUpdateCount, 1)

    clock.date += 1000
    controller.controls.withLock { $0?.yield(throwing: SomeError()) }
    expectNoDifference(store.error as? SomeError, SomeError())
    expectNoDifference(store.errorLastUpdatedAt, clock.date)
    expectNoDifference(store.errorUpdateCount, 2)

    clock.date += 1000
    _ = try? await store.mutate(with: "foo")
    expectNoDifference(
      store.error as? FailableMutation.MutateError,
      FailableMutation.MutateError()
    )
    expectNoDifference(store.errorLastUpdatedAt, clock.date)
    expectNoDifference(store.errorUpdateCount, 3)
  }

  @Test("Yields Multiple Values During Mutation")
  func yieldsMultipleValuesDuringMutation() async throws {
    let mutation = ContinuingMutation()
    let store = self.client.store(for: mutation)
    let collector = MutationStoreEventsCollector<
      ContinuingMutation.Arguments, ContinuingMutation.ReturnValue
    >()
    let value = try await store.mutate(with: "foo", handler: collector.eventHandler())

    collector.expectEventsMatch([
      .stateChanged,
      .mutatingStarted("foo"),
      .mutationResultReceived("foo", .success(ContinuingMutation.values[0])),
      .stateChanged,
      .mutationResultReceived("foo", .success(ContinuingMutation.values[1])),
      .stateChanged,
      .mutationResultReceived("foo", .success(ContinuingMutation.values[2])),
      .stateChanged,
      .mutationResultReceived("foo", .success(ContinuingMutation.finalValue)),
      .stateChanged,
      .mutatingEnded("foo")
    ])
    expectNoDifference(value, ContinuingQuery.finalValue)
  }

  @Test("Yields Error Then Success During Mutation")
  func yieldsErrorThenSuccessDuringMutation() async throws {
    let mutation = ContinuingErrorMutation()
    let store = self.client.store(for: mutation)
    let collector = MutationStoreEventsCollector<
      ContinuingErrorMutation.Arguments, ContinuingErrorMutation.ReturnValue
    >()
    let value = try await store.mutate(with: "foo", handler: collector.eventHandler())

    collector.expectEventsMatch([
      .stateChanged,
      .mutatingStarted("foo"),
      .mutationResultReceived("foo", .failure(ContinuingErrorMutation.SomeError())),
      .stateChanged,
      .mutationResultReceived("foo", .success(ContinuingErrorMutation.finalValue)),
      .stateChanged,
      .mutatingEnded("foo")
    ])
    expectNoDifference(value, ContinuingErrorQuery.finalValue)
    expectNoDifference(store.error as? ContinuingErrorQuery.SomeError, nil)
    expectNoDifference(store.errorLastUpdatedAt != nil, true)
  }

  @Test("Yields Value Then Error During Mutation")
  func yieldsValueThenErrorDuringMutation() async throws {
    let mutation = ContinuingValueThenErrorMutation()
    let store = self.client.store(for: mutation)
    let collector = MutationStoreEventsCollector<
      ContinuingValueThenErrorMutation.Arguments, ContinuingValueThenErrorMutation.ReturnValue
    >()
    let value = try? await store.mutate(with: "foo", handler: collector.eventHandler())

    collector.expectEventsMatch([
      .stateChanged,
      .mutatingStarted("foo"),
      .mutationResultReceived("foo", .success(ContinuingValueThenErrorMutation.value)),
      .stateChanged,
      .mutationResultReceived("foo", .failure(ContinuingValueThenErrorMutation.SomeError())),
      .stateChanged,
      .mutatingEnded("foo")
    ])
    expectNoDifference(value, nil)
    expectNoDifference(
      store.error as? ContinuingValueThenErrorMutation.SomeError,
      ContinuingValueThenErrorMutation.SomeError()
    )
  }

  @Test("Reset State, Empties Task History")
  func cancelAllActiveTasksUpdatesTaskHistoryEntry() async throws {
    let store = self.client.store(for: EmptyMutation())
    try await store.mutate(with: "blob")
    store.resetState()
    expectNoDifference(store.history.isEmpty, true)
  }

  @Test("Reset State, Cancels Tasks")
  func cancelAllActiveTasksCancelsTasks() async throws {
    let store = self.client.store(for: EmptyMutation())
    let task = store.mutateTask(with: "blob")
    store.resetState()
    await #expect(throws: CancellationError.self) {
      try await task.runIfNeeded()
    }
  }

  @Test("Reset State, Current Value Is Initial")
  func resetStateCurrentValueIsInitial() async throws {
    let store = self.client.store(for: EmptyMutation())
    try await store.mutate(with: "blob")
    store.resetState()
    expectNoDifference(store.currentValue, nil)
    expectNoDifference(store.valueLastUpdatedAt, nil)
    expectNoDifference(store.valueUpdateCount, 0)
  }

  @Test("Reset State, Current Error Is Nil")
  func resetStateCurrentErrorIsNil() async throws {
    let store = self.client.store(for: FailableMutation())
    _ = try? await store.mutate(with: "blob")
    store.resetState()
    expectNoDifference(store.error == nil, true)
    expectNoDifference(store.errorLastUpdatedAt, nil)
    expectNoDifference(store.errorUpdateCount, 0)
  }

  @Test("1-Lengthed History, Only Keeps Most Recent Attempt")
  func noHistoryOnlyKeepsMostRecentAttempt() async throws {
    let store = self.client.store(for: EmptyMutation().maxHistory(length: 1))
    try await store.mutate(with: "blob")

    expectNoDifference(try? store.history[0].currentResult?.get(), "blob")
    expectNoDifference(store.history.count, 1)

    try await store.mutate(with: "blob jr")
    expectNoDifference(try? store.history[0].currentResult?.get(), "blob jr")
    expectNoDifference(store.history.count, 1)
  }

  #if swift(>=6.2) && SWIFT_QUERY_EXIT_TESTABLE
    @Test("History Length Must Be Greater Than Zero")
    func historyLengthMustBeGreaterThanZero() async {
      await #expect(
        processExitsWith: .failure,
        Comment(rawValue: _tooSmallMutationHistoryLengthMessage(got: 0))
      ) {
        _ = EmptyMutation().maxHistory(length: 0)
      }
    }
  #endif

  @Test("Fixed Length History, Cycles Out Old Attempts")
  func fixedLengthHistoryCyclesOutOldAttempts() async throws {
    let store = self.client.store(for: EmptyMutation().maxHistory(length: 2))
    try await store.mutate(with: "blob")
    try await store.mutate(with: "blob jr")
    try await store.mutate(with: "blob sr")

    expectNoDifference(try? store.history[0].currentResult?.get(), "blob jr")
    expectNoDifference(try? store.history[1].currentResult?.get(), "blob sr")
    expectNoDifference(store.history.count, 2)
  }

  @Test("Fixed Length History, Ignores Results From Old Attempts")
  func fixedLengthHistoryIgnoresResultsFromOldAttempts() async throws {
    let mutation = FailableMutation()
    mutation.state.withLock { $0 = "blob" }

    let store = self.client.store(for: mutation.maxHistory(length: 2))
    let task = store.mutateTask(with: "blob")
    try await store.mutate(with: "blob jr")
    try await store.mutate(with: "blob sr")

    mutation.state.withLock { $0 = nil }
    await #expect(throws: FailableMutation.MutateError.self) {
      try await task.runIfNeeded()
    }

    expectNoDifference(store.error == nil, true)
    expectNoDifference(try? store.history[0].currentResult?.get(), "blob")
    expectNoDifference(try? store.history[1].currentResult?.get(), "blob")
    expectNoDifference(store.history.count, 2)
    expectNoDifference(store.errorUpdateCount, 0)
  }
}
