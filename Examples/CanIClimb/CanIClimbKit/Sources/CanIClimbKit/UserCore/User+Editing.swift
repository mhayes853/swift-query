import Dependencies
import Foundation
import SharingQuery
import SwiftNavigation

// MARK: - Edit

extension User {
  public struct Edit: Hashable, Sendable, Codable {
    public var name: PersonNameComponents
    public var subtitle: String

    public init(name: PersonNameComponents, subtitle: String) {
      self.name = name
      self.subtitle = subtitle
    }
  }
}

// MARK: - Editor

extension User {
  public protocol Editor: Sendable {
    func editUser(with edit: Edit) async throws -> User
  }

  public enum EditorKey: DependencyKey {
    public static let liveValue: any User.Editor = CanIClimbAPI.shared
  }
}

extension CanIClimbAPI: User.Editor {}

extension User {
  @MainActor
  public final class MockEditor: Editor {
    public private(set) var edits = [Edit]()
    public var result: Result<User, any Error>

    public init(result: Result<User, any Error>) {
      self.result = result
    }

    public func editUser(with edit: User.Edit) async throws -> User {
      self.edits.append(edit)
      return try self.result.get()
    }
  }
}

extension User {
  public struct PassthroughEditor: Editor {
    public init() {}

    public func editUser(with edit: User.Edit) async throws -> User {
      User(id: User.mock1.id, name: edit.name, subtitle: edit.subtitle)
    }
  }
}

// MARK: - Mutation

extension User {
  public static let editMutation = EditMutation()
    .alerts(success: .editProfileSuccess, failure: .editProfileFailure)

  public struct EditMutation: MutationRequest, Hashable {
    public struct Arguments: Sendable {
      let edit: User.Edit

      public init(edit: User.Edit) {
        self.edit = edit
      }
    }

    public func mutate(
      with arguments: Arguments,
      in context: QueryContext,
      with continuation: QueryContinuation<User>
    ) async throws -> User {
      @Dependency(\.defaultQueryClient) var client
      @Dependency(User.EditorKey.self) var editor
      @Dependency(CurrentUser.self) var currentUser

      let user = try await currentUser.edit(with: arguments.edit, using: editor)
      client.store(for: User.currentQuery).currentValue = user
      return user
    }
  }
}

// MARK: - AlertState

extension AlertState where Action == Never {
  public static let editProfileSuccess = Self {
    TextState("Success")
  } message: {
    TextState("Your profile has been updated.")
  }

  public static let editProfileFailure = Self.remoteOperationError {
    TextState("Failed to Edit Your Profile")
  } message: {
    TextState("Your profile could not be edited. Please try again later.")
  }
}
