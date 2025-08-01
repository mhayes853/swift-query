import CoreLocation
import Dependencies
import Query

// MARK: - UserLocation

public protocol UserLocation: Sendable {
  func read() async throws -> LocationReading
  func requestAuthorization() async -> Bool
}

public enum UserLocationKey: DependencyKey {
  public static var liveValue: any UserLocation {
    fatalError("Set this value on the MainActor at the root.")
  }
}

// MARK: - MockUserLocation

@MainActor
public final class MockUserLocation {
  private struct NoReadingError: Error {}

  public var currentReading = Result<LocationReading, any Error>.failure(NoReadingError())
  public var isAuthorized = true

  public init() {}
}

extension MockUserLocation: UserLocation {
  public func read() async throws -> LocationReading {
    try self.currentReading.get()
  }

  public func requestAuthorization() async -> Bool {
    self.isAuthorized
  }
}

// MARK: - RequestUserPermissionMutation

extension LocationReading {
  public static let requestUserPermissionMutation = RequestUserPermissionMutation()

  public struct RequestUserPermissionMutation: MutationRequest, Hashable {
    public typealias Arguments = Void

    public func mutate(
      with arguments: Void,
      in context: QueryContext,
      with continuation: QueryContinuation<Bool>
    ) async -> Bool {
      @Dependency(\.defaultQueryClient) var client
      @Dependency(UserLocationKey.self) var userLocation
      let isAuthorized = await userLocation.requestAuthorization()
      if isAuthorized {
        Task.immediate { try await client.store(for: LocationReading.userQuery).fetch() }
      }
      return isAuthorized
    }
  }
}

// MARK: - UserQuery

extension LocationReading {
  public static let userQuery = UserQuery().stale(after: TimeInterval(duration: .fiveMinutes)).logDuration()

  public struct UserQuery: QueryRequest, Hashable {
    public func fetch(
      in context: QueryContext,
      with continuation: QueryContinuation<LocationReading>
    ) async throws -> LocationReading {
      @Dependency(UserLocationKey.self) var userLocation
      return try await userLocation.read()
    }
  }
}
