extension QueryRequest {
  /// Indicates that the query runs completely offline, and therefore does not attempt to make any
  /// network connections.
  ///
  /// > Warning: Only use this modifier if your query does not attempt to connect to the network in
  /// > any way shape or form. Otherwise, you'll lose out on benefits such as automatic refetching
  /// > when the user's network comes back online after being offline.
  ///
  /// Some queries may not require access to the internet or an external network, and run entirely
  /// locally on the user's device. Examples of this may be running expensive and time-consuming
  /// computations from local file data on a background thread, running an expensive SQL query on a
  /// SQLite database, or streaming data from a locally running LLM.
  ///
  /// - Parameter isOffline: Whether the query is completely offline. Defaults to `true`.
  /// - Returns: A ``ModifiedQuery``.
  public func completelyOffline(
    _ isOffline: Bool = true
  ) -> ModifiedQuery<Self, _CompletelyOfflineModifier<Self>> {
    self.modifier(_CompletelyOfflineModifier(isOffline: isOffline))
  }
}

public struct _CompletelyOfflineModifier<Query: QueryRequest>: _ContextUpdatingQueryModifier {
  let isOffline: Bool

  public func setup(context: inout QueryContext) {
    context.satisfiedConnectionStatus = self.isOffline ? .disconnected : .connected
  }
}
