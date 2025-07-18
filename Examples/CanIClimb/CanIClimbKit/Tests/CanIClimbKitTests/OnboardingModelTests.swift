import CanIClimbKit
import CustomDump
import DependenciesTestSupport
import Foundation
import SharingGRDB
import SharingQuery
import Testing

extension DependenciesTestSuite {
  @MainActor
  @Suite(
    "OnboardingModel tests",
    .dependencies {
      $0[HealthPermissions.self] = HealthPermissions(
        database: $0.defaultDatabase,
        requester: HealthPermissions.MockRequester()
      )
    }
  )
  struct OnboardingModelTests {
    @Test("Onboarding Flow, Finishes Once")
    func onboardingFlowFinishesOnce() async throws {
      try await withDependencies {
        $0[UserLocationKey.self] = MockUserLocation()
      } operation: {
        var didFinishCount = 0
        let model = OnboardingModel()
        model.onFinished = { didFinishCount += 1 }

        expectNoDifference(didFinishCount, 0)
        try await model.runOnboardingFlow(fillingIn: .mock)
        expectNoDifference(didFinishCount, 1)
      }
    }

    @Test("Onboarding Flow, Saves Record")
    func onboardingFlowSavesRecord() async throws {
      try await withDependencies {
        $0[UserLocationKey.self] = MockUserLocation()
      } operation: {
        @Dependency(\.defaultDatabase) var database

        let model = OnboardingModel()
        try await model.runOnboardingFlow(fillingIn: .mock)

        let record = try await database.read { UserHumanityRecord.find(in: $0) }
        expectNoDifference(record, .mock)
      }
    }

    @Test("Onboarding Flow, Marks Onboarding Complete")
    func onboardingFlowMarksOnboardingComplete() async throws {
      try await withDependencies {
        $0[UserLocationKey.self] = MockUserLocation()
      } operation: {
        @Dependency(\.defaultDatabase) var database

        let model = OnboardingModel()

        var record = try await database.read { InternalMetricsRecord.find(in: $0) }
        expectNoDifference(record.hasCompletedOnboarding, false)

        try await model.runOnboardingFlow(fillingIn: .mock)

        record = try await database.read { InternalMetricsRecord.find(in: $0) }
        expectNoDifference(record.hasCompletedOnboarding, true)
      }
    }

    @Test(
      "Onboarding Flow, Sets Averages For Other Profile Fields When Gender Selected",
      arguments: [HumanGender.male, .female, .nonBinary]
    )
    func setsAveragesForOtherProfileFieldsWhenGenderSelectedForFirstTime(gender: HumanGender) {
      let model = OnboardingModel()

      model.genderSelected(gender)
      expectNoDifference(model.userProfile.weight, gender.averages.weight)
      expectNoDifference(model.userProfile.height, gender.averages.height)

      let newLbs = Measurement<UnitMass>(value: 100, unit: .pounds)
      model.userProfile.weight = newLbs
      model.genderSelected(.male)
      expectNoDifference(
        model.userProfile.weight,
        newLbs,
        "A second gender selection should not update the preselected averages."
      )
    }

    @Test("Persists Metric Preference When Changed")
    func persistsMetricPreferenceWhenChanged() async throws {
      let model = OnboardingModel()

      model.metricPreference = .metric

      let model2 = OnboardingModel()
      expectNoDifference(model2.metricPreference, .metric)
    }

    @Test("Onboarding Flow With Sign In, Finishes Properly")
    func onboardingFlowWithSignIn() async throws {
      let authenticator = User.MockAuthenticator()
      authenticator.requiredCredentials = .mock1

      try await withDependencies {
        $0[User.AuthenticatorKey.self] = authenticator
        $0[User.CurrentLoaderKey.self] = User.MockCurrentLoader(result: .success(.mock1))
      } operation: {
        @Dependency(\.defaultQueryClient) var client

        let model = OnboardingModel()
        try await model.runOnboardingFlow(
          fillingIn: .mock,
          locationPermissions: .skip,
          signInCredentials: .mock1,
          connectHealthKit: .skip
        )

        let userStore = client.store(for: User.currentQuery)
        _ = try? await userStore.activeTasks.first?.runIfNeeded()
        expectNoDifference(userStore.currentValue, .mock1)
      }
    }
  }
}

extension OnboardingModel {
  func runOnboardingFlow(
    fillingIn record: UserHumanityRecord,
    locationPermissions: LocationPermissionStepAction = .requestPermission,
    signInCredentials: User.SignInCredentials? = nil,
    connectHealthKit: ConnectToHealthKitStepAction = .connect
  ) async throws {
    self.startInvoked()
    expectNoDifference(self.path, [.disclaimer])

    self.hasAcceptedDisclaimer = true
    self.disclaimerAccepted()
    expectNoDifference(self.path.last, .selectGender)

    self.genderSelected(record.gender)
    expectNoDifference(self.path.last, .selectAgeRange)

    self.ageRangeSelected(record.ageRange)
    expectNoDifference(self.path.last, .selectHeight)

    self.userProfile.height = record.height
    self.heightSelected()
    expectNoDifference(self.path.last, .selectWeight)

    self.userProfile.weight = record.weight
    self.weightSelected()
    expectNoDifference(self.path.last, .selectActivityLevel)

    self.activityLevelSelected(record.activityLevel)
    expectNoDifference(self.path.last, .selectWorkoutFrequency)

    self.workoutFrequencySelected(record.workoutFrequency)
    expectNoDifference(self.path.last, .connectHealthKit)

    await self.connectToHealthKitStepInvoked(action: connectHealthKit)
    expectNoDifference(self.connectToHealthKit.isConnected, connectHealthKit == .connect)
    expectNoDifference(self.path.last, .shareLocation)

    @SharedQuery(LocationReading.requestUserPermissionMutation) var request
    expectNoDifference($request.valueUpdateCount, 0)
    await self.locationPermissionStepInvoked(action: locationPermissions)
    if locationPermissions == .requestPermission {
      expectNoDifference($request.valueUpdateCount, 1)
      expectNoDifference(self.hasRequestedLocationSharing, true)
      expectNoDifference(self.isLocationSharingEnabled, request)
    } else {
      expectNoDifference($request.valueUpdateCount, 0)
      expectNoDifference(self.hasRequestedLocationSharing, false)
      expectNoDifference(self.isLocationSharingEnabled, false)
    }
    expectNoDifference(self.path.last, .signIn)

    if let signInCredentials {
      try await self.signIn.credentialsReceived(.success(signInCredentials))
    } else {
      self.signInSkipped()
    }
    expectNoDifference(self.path.last, .wrapUp)

    try await self.wrapUpInvoked()
  }
}

extension UserHumanityRecord {
  static let mock = UserHumanityRecord(
    height: .imperial(HumanHeight.Imperial(feet: 6, inches: 1)),
    weight: Measurement(value: 180, unit: .pounds),
    ageRange: .in30s,
    gender: .male,
    activityLevel: .somewhatActive,
    workoutFrequency: .everyOtherDay
  )
}
