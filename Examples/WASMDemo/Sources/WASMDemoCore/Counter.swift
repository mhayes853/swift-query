import Foundation
import JavaScriptKit
import Observation
import SharingQuery
import SwiftNavigation

// MARK: - CounterModel

@MainActor
@Observable
public final class CounterModel: Identifiable {
  @ObservationIgnored
  @SharedQuery<NumberFact.Query.State> public var fact: NumberFact?

  @ObservationIgnored
  @SharedQuery<NumberFact.NthPrimeQuery.State> public var nthPrime: Int??

  public private(set) var count: Int

  public init(startingAt number: Int = 0) {
    self.count = number
    self._fact = SharedQuery(NumberFact.query(for: number))
    self._nthPrime = SharedQuery(NumberFact.nthPrimeQuery(for: number))
  }
}

extension CounterModel {
  public func incremented() {
    self.jumped(to: self.count + 1)
  }

  public func decremented() {
    self.jumped(to: self.count - 1)
  }
}

extension CounterModel {
  public func jumped(to number: Int) {
    self.count = number
    self.$fact = SharedQuery(NumberFact.query(for: number))
    self.$nthPrime = SharedQuery(NumberFact.nthPrimeQuery(for: number))
  }
}

// MARK: - Render Counter

@MainActor
private var tokens = Set<ObserveToken>()

@MainActor
public func renderCounter(using model: CounterModel, in container: JSObject) {
  let counterContainer = document.createElement!("div")
  _ = container.appendChild!(counterContainer)

  renderCounterLabels(title: "Count", using: model, in: counterContainer.object!)

  let increment = document.createElement!("button")
  increment.innerText = "Increment"
  increment.onclick = .object(
    JSClosure { _ in
      model.incremented()
      return .undefined
    }
  )
  _ = container.appendChild!(increment)

  let decrement = document.createElement!("button")
  decrement.innerText = "Decrement"
  decrement.onclick = .object(
    JSClosure { _ in
      model.decremented()
      return .undefined
    }
  )
  _ = container.appendChild!(decrement)

  renderJumpButton(for: 100, using: model, in: container)
  renderJumpButton(for: 1000, using: model, in: container)
  renderJumpButton(for: 10_000, using: model, in: container)
  renderJumpButton(for: 100_000, using: model, in: container)
  renderJumpButton(for: 1_000_000, using: model, in: container)
}

@MainActor
private func renderJumpButton(
  for number: Int,
  using model: CounterModel,
  in container: JSObject
) {
  let jump = document.createElement!("button")
  jump.innerText = .string("Jump to \(number)")
  jump.onclick = .object(
    JSClosure { _ in
      model.jumped(to: number)
      return .undefined
    }
  )
  _ = container.appendChild!(jump)
}

// MARK: - Render Counter Labels

@MainActor
public func renderCounterLabels(
  title: String,
  using model: CounterModel,
  in container: JSObject
) {
  let countLabel = document.createElement!("h3")
  let factLabel = document.createElement!("p")
  let nthPrimeLabel = document.createElement!("p")

  _ = container.appendChild!(countLabel)
  _ = container.appendChild!(factLabel)
  _ = container.appendChild!(nthPrimeLabel)

  observe {
    countLabel.innerText = .string("\(title) \(model.count)")

    switch model.$fact.status {
    case let .result(.success(fact)):
      factLabel.innerText = .string(fact.content)
      factLabel.style.color = "black"

    case let .result(.failure(error)):
      factLabel.innerText = .string("Error: \(error.localizedDescription)")
      factLabel.style.color = "red"

    default:
      factLabel.innerText = .string(model.fact?.content ?? "Loading Fact...")
      factLabel.style.color = "gray"
    }

    if let prime = model.nthPrime {
      if let prime {
        nthPrimeLabel.innerText = .string(
          "The \(model.count.nthFormatted) prime number is \(prime)!"
        )
      } else {
        nthPrimeLabel.innerText = .string("There is no \(model.count.nthFormatted) prime number...")
      }
      nthPrimeLabel.style.color = "black"
    } else {
      nthPrimeLabel.innerText = .string("Loading \(model.count.nthFormatted) prime number...")
      nthPrimeLabel.style.color = "gray"
    }
  }
  .store(in: &tokens)
}
