import CustomDump
import Foundation
import Query
import Testing

@Suite("QueryBackoffFunction tests")
struct QueryBackoffFunctionTests {
  @Test(
    "Exponential",
    arguments: [(0, 0), (1, 1000), (2, 2000), (3, 4000), (4, 8000), (5, 16000)]
  )
  func exponential(n: Int, e: TimeInterval) {
    let function = QueryBackoffFunction.exponential(1000)
    expectNoDifference(function(n), e)
  }

  @Test(
    "Linear",
    arguments: [(0, 0), (1, 1000), (2, 2000), (3, 3000), (4, 4000), (5, 5000)]
  )
  func linear(n: Int, e: TimeInterval) {
    let function = QueryBackoffFunction.linear(1000)
    expectNoDifference(function(n), e)
  }

  @Test("Fibonacci", arguments: [(0, 0), (1, 1000), (2, 1000), (3, 2000), (4, 3000), (5, 5000)])
  func fibonacci(n: Int, e: TimeInterval) {
    let function = QueryBackoffFunction.fibonacci(1000)
    expectNoDifference(function(n), e)
  }

  @Test("Jittered Selects Random Value Based On Generator")
  func jitterUsesDifferentValuesForExponential() {
    let function = QueryBackoffFunction.exponential(1000).jittered(using: ZeroRandomGenerator())
    expectNoDifference(function(10), 0)
  }

  @Test(
    "CustomStringConvertible",
    arguments: [
      (QueryBackoffFunction { _ in 10 }, "Custom"),
      (QueryBackoffFunction("Blob") { _ in 10 }, "Blob"),
      (.linear(10), "Linear every 10.0 secs"),
      (.exponential(1), "Exponential every 1.0 sec"),
      (.constant(2).jittered(), "Constant 2.0 secs with jitter")
    ]
  )
  func customStringConvertibleWithBackoffFunction(
    function: QueryBackoffFunction,
    string: String
  ) {
    expectNoDifference(function.description, "QueryBackoffFunction(\(string))")
  }
}

private struct ZeroRandomGenerator: RandomNumberGenerator {
  func next() -> UInt64 {
    0
  }
}
