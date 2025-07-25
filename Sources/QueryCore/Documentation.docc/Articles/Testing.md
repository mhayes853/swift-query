# Testing

Learn how to best use the library in your app's test suite.

## Overview

Given that testing is only sometimes considered a crucial software development practice, it would be wise to test how your queries interact with your app. In general, reliably testing code that utilizes async await can be challenging due to the challenges of managing the time of a Task's execution. However, depending on your usage, you can utilize the tools in the library to make this process easier.

If your queries rely on the default initializer of ``QueryClient``, then retries, backoff, artificial delays, refetching on network reconnection, and refetching on the app reentering from the background are disabled when running queries in a test environment.

Let's take a look at how we can test queries depending on your usage of the library.

## Reliable and Deterministic Tests

Depending on your usage of the library, you may implement a class `SomeModel` that utilizes `SomeData.query` in the following ways.

**Sharing**
```swift
import Observation
import SharingQuery

@MainActor
@Observable
final class SomeModel {
  @ObservationIgnored
  @SharedQuery(SomeData.query) var value
}
```

**Combine**
```swift
import Query
import Combine

@MainActor
final class SomeModel: ObservableObject {
  @Published var value: String?
  private var cancellables = Set<AnyCancellable>()

  init(
    client: QueryClient,
    scheduler: some Scheduler = DispatchQueue.main
  ) {
    let store = client.store(for: SomeData.query)
    store
      .publisher
      .receive(on: scheduler)
      .sink { [weak self] output in
        self?.value = output.state.currentValue
      }
      .store(in: &cancellables)
  }
}
```

**Pure Swift (With Observation)**
```swift
import Observation
import Query

@MainActor
@Observable
final class SomeModel {
  var value: String?

  @ObservationIgnored private var subscriptions = Set<QuerySubscription>()

  init(client: QueryClient) {
    let store = client.store(for: SomeData.query)
    store.subscribe(
      with: QueryEventHandler { [weak self] state, _ in
        Task { @MainActor in
          self?.value = state.currentValue
        }
      }
    )
    .store(in: &subscriptions)
  }
}
```

In a test suite, your first instinct may be to assert on `value`. However, `value` will likely be in a loading state once the test begins, and it's difficult to determine when it will have been loaded.

> Note: If you're code follows the Sharing example, you will override `@Dependency(\.queryClient)` instead of passing a `QueryClient` to `SomeModel`'s initializer.

```swift
@Test
@MainActor
func valueLoads() {
  let model = SomeModel(client: QueryClient())
  #expect(model.value == nil)

  // Wait for value to load...

  #expect(model.value == "loaded")
}
```

The main issue here is the "Wait for value to load..." comment as it's not exactly clear when `model.value` will have been loaded. To get around this, you can technically reach into the ``QueryStore`` for `SomeData.query`, and await the first active task in the store.

```swift
@Test
@MainActor
func valueLoads() async throws {
  let client = QueryClient()

  let model = SomeModel(client: client)
  #expect(model.value == nil)

  let store = client.store(for: SomeData.query)
  _ = try await store.activeTasks.first?.runIfNeeded()

  #expect(model.value == "loaded")
}
```

This will work, yet it's a quite annoying syntax.

Another approach is to override the defaults applied to each query in the `QueryClient` such that automatic fetching is disabled. That way, you can manually trigger the query's execution. You can do this by providing a custom value to the `storeCreator` parameter in `QueryClient`'s initializer.

```swift
@Test
@MainActor
func valueLoads() async throws {
  let client = QueryClient(
    storeCreator: .default(
      retryLimit: 0,
      backoff: .noBackoff,
      delayer: .noDelay,
      queryEnableAutomaticFetchingCondition: .always(false),
      networkObserver: nil,
      focusCondition: nil
    )
  )

  let model = SomeModel(client: client)
  #expect(model.value == nil)

  try await client.store(for: SomeData.query).fetch()

  #expect(model.value == "loaded")
}
```

> Note: If your code follows the Sharing example, you can use the `@SharedQuery` property wrapper directly to fetch the data.
>
> ```swift
> @Test
> @MainActor
> func valueLoads() async throws {
>   let client = QueryClient(
>     storeCreator: .default(
>       retryLimit: 0,
>       backoff: .noBackoff,
>       delayer: .noDelay,
>       queryEnableAutomaticFetchingCondition: .always(false),
>       networkObserver: nil,
>       focusCondition: nil
>     )
>   )
>
>   let model = SomeModel(client: client)
>   #expect(model.value == nil)
>
>   try await model.$value.load()
>
>   #expect(model.value == "loaded")
> }
> ```

Now you can manually trigger execution of the query, ensuring that we have a deterministic way to assert on the model's value.

## Conclusion

The biggest hurdle in testing how your code interacts with your queries is managing to have control over the query's execution. To clear this hurdle, you can either reach into the `QueryStore` and await the first active ``QueryTask``, or you can override the `QueryClient` to disable automatic fetching.
