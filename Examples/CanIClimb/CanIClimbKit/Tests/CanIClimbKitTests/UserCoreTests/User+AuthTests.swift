import CanIClimbKit
import CustomDump
import DependenciesTestSupport
import Foundation
import SharingGRDB
import SharingQuery
import Synchronization
import Testing

extension DependenciesTestSuite {
  @MainActor
  @Suite("User+Auth tests")
  struct UserAuthTests {
    @Test("Loads Current User When Signed In")
    func loadsCurrentUserWhenSignedIn() async throws {
      let authenticator = User.MockAuthenticator()
      try await withDependencies {
        $0[CurrentUser.self] = CurrentUser(database: $0.defaultDatabase)
        $0[User.AuthenticatorKey.self] = authenticator
        $0[User.CurrentLoaderKey.self] = User.MockCurrentLoader(result: .success(.mock1))
      } operation: {
        @Dependency(\.defaultQueryClient) var client
        let signInStore = client.store(for: User.signInMutation)
        let userStore = client.store(for: User.currentQuery)

        authenticator.requiredCredentials = .mock1
        try await signInStore.mutate(with: User.SignInMutation.Arguments(credentials: .mock1))

        let task = userStore.activeTasks.first
        _ = try? await task?.runIfNeeded()
        expectNoDifference(userStore.currentValue, .mock1)
      }
    }

    @Test("Sets Current User to Nil When Sign Out Successful")
    func setsCurrentUserToNilWhenSignOutSuccessful() async throws {
      @Dependency(\.defaultDatabase) var database

      let authenticator = User.MockAuthenticator()
      let userStorage = CurrentUser(database: database)
      try await withDependencies {
        $0[CurrentUser.self] = userStorage
        $0[User.AuthenticatorKey.self] = authenticator
        $0[User.CurrentLoaderKey.self] = User.MockCurrentLoader(result: .success(.mock1))
      } operation: {
        @Dependency(\.defaultQueryClient) var client
        let userStore = client.store(for: User.currentQuery)
        let signOutStore = client.store(for: User.signOutMutation)

        try await userStore.fetch()

        expectNoDifference(authenticator.signOutCount, 0)
        expectNoDifference(userStore.currentValue, .mock1)
        try await signOutStore.mutate()
        expectNoDifference(authenticator.signOutCount, 1)
        expectNoDifference(userStore.currentValue, nil)
        expectNoDifference(userStore.error is User.UnauthorizedError, true)

        let localUser = try await userStorage.localUser()
        expectNoDifference(localUser, nil)
      }
    }
  }
}
