import Observation
import SharingGRDB
import SharingQuery
import SwiftUI
import SwiftUINavigation

// MARK: - ConnectToHealthKitModel

@MainActor
@Observable
public final class ConnectToHealthKitModel {
  @ObservationIgnored
  @Fetch(wrappedValue: LocalInternalMetricsRecord(), .singleRow(LocalInternalMetricsRecord.self))
  private var _localMetrics

  @ObservationIgnored
  @SharedQuery(HealthPermissions.requestMutation) private var request: Void?

  public init() {}
}

extension ConnectToHealthKitModel {
  public var isConnected: Bool {
    self._localMetrics.hasConnectedHealthKit
  }

  public func connectInvoked() async {
    try? await self.$request.mutate()
  }
}
