import Dependencies
import Observation
import Query
import SharingGRDB
import SwiftUI
import SwiftUINavigation

// MARK: - CanIClimbModel

@MainActor
@Observable
public final class CanIClimbModel {
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database

  public var devTools: QueryDevToolsModel?

  public var destination: Destination? {
    didSet { self.bind() }
  }

  @ObservationIgnored
  @Dependency(\.notificationCenter) var center

  @ObservationIgnored
  @Dependency(ApplicationLaunch.ID.self) var launchId

  @ObservationIgnored
  @Dependency(DeviceInfo.self) var deviceInfo

  private var token: NotificationCenter.ObservationToken?

  public init() {}
}

extension CanIClimbModel {
  public func appeared() async throws {
    self.token = self.center.addObserver(for: DeviceShakeMessage.self) { [weak self] _ in
      self?.devTools = self?.devTools ?? QueryDevToolsModel()
    }
    let hasFinishedOnboarding = try await self.database.write { [launchId, deviceInfo] db in
      try ApplicationLaunchRecord.insert {
        ApplicationLaunchRecord(id: launchId, localizedDeviceName: deviceInfo.localizedModelName)
      }
      .execute(db)
      return InternalMetricsRecord.find(in: db).hasCompletedOnboarding
    }
    if !hasFinishedOnboarding {
      self.destination = .onboarding(OnboardingModel())
    }
  }

  public func disappeared() {
    guard let token else { return }
    self.center.removeObserver(token)
  }
}

extension CanIClimbModel {
  public func settingsInvoked() {
    self.destination = .settings(SettingsModel())
  }
}

extension CanIClimbModel {
  @CasePathable
  public enum Destination: Hashable, Sendable {
    case onboarding(OnboardingModel)
    case settings(SettingsModel)
  }

  private func bind() {
    switch self.destination {
    case .onboarding(let model):
      model.onFinished = { [weak self] in self?.destination = nil }
    default:
      break
    }
  }
}

// MARK: - CanIClimbApp

public struct CanIClimbApp: App {
  private let model: CanIClimbModel

  public init() {
    try! prepareDependencies {
      $0.defaultQueryClient = QueryClient(storeCreator: .canIClimb)
      $0.defaultDatabase = try canIClimbDatabase(
        url: .applicationSupportDirectory.appending(path: "db/can-i-climb.db")
      )
      $0.defaultSyncEngine = try .canIClimb(writer: $0.defaultDatabase)
      $0[UserLocationKey.self] = CLUserLocation()
      $0[DeviceInfo.self] = DeviceInfo.current
    }
    self.model = CanIClimbModel()
  }

  public var body: some Scene {
    WindowGroup {
      CanIClimbView(model: self.model)
    }
  }
}

// MARK: - CanIClimbView

public struct CanIClimbView: View {
  @Bindable private var model: CanIClimbModel

  public init(model: CanIClimbModel) {
    self.model = model
  }

  public var body: some View {
    Text("TODO")
      .observeQueryAlerts()
      .task { try? await self.model.appeared() }
      .onDisappear { self.model.disappeared() }
      .sheet(item: self.$model.devTools) { model in
        QueryDevToolsView(model: model)
      }
      #if os(iOS)
        .shakeDetection()
        .fullScreenCover(item: self.$model.destination.onboarding) { model in
          OnboardingView(model: model)
        }
      #else
        .sheet(item: self.$model.destination.onboarding) { model in
          OnboardingView(model: model)
        }
      #endif
  }
}
