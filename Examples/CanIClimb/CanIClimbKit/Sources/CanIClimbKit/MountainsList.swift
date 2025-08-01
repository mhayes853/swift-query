import Dependencies
import MapKit
import Observation
import Sharing
import SharingQuery
import SwiftUI
import SwiftUINavigation

// MARK: - MountainsListModel

@MainActor
@Observable
public final class MountainsListModel {
  @ObservationIgnored
  @SharedQuery(Mountain.searchQuery(.recommended)) public var mountains

  public var searchText = "" {
    didSet { self.debounceTask?.schedule() }
  }
  public var category = Mountain.Search.Category.recommended {
    didSet { self.updateMountainsQuery() }
  }

  public var destination: Destination?

  @ObservationIgnored private var debounceTask: DebounceTask?

  @ObservationIgnored
  @Dependency(\.continuousClock) private var clock

  public init(searchDebounceDuration: Duration = .seconds(0.5)) {
    self.debounceTask = DebounceTask(
      clock: self.clock,
      duration: searchDebounceDuration
    ) { [weak self] in
      await self?.updateMountainsQuery()
    }
  }
}

extension MountainsListModel {
  private func updateMountainsQuery() {
    let search = Mountain.Search(text: self.searchText, category: self.category)
    self.$mountains = SharedQuery(Mountain.searchQuery(search))
  }
}

extension MountainsListModel {
  @CasePathable
  public enum Destination: Hashable, Sendable {
    case settings(SettingsModel)
    case mountainDetail(MountainDetailModel)
  }
}

extension MountainsListModel {
  public func settingsInvoked() {
    self.destination = .settings(SettingsModel())
  }
}

extension MountainsListModel {
  public func mountainDetailInvoked(for id: Mountain.ID) {
    self.destination = .mountainDetail(MountainDetailModel(id: id))
  }
}

// MARK: - MountainsListView

public struct MountainsListView<SheetContent: View>: View {
  @Bindable private var model: MountainsListModel
  private let sheetContent: (AnyView) -> SheetContent
  @State private var selectedDetent = PresentationDetent.medium

  public init(model: MountainsListModel, sheetContent: @escaping (AnyView) -> SheetContent) {
    self.model = model
    self.sheetContent = sheetContent
  }

  public var body: some View {
    MountainsListMapView(model: self.model)
      .sheet(isPresented: .constant(true)) {
        let content = MountainsListSheetContentView(
          model: self.model,
          isFullScreen: self.selectedDetent == .large
        )
        .presentationDetents(
          [.height(200), .medium, .large],
          selection: self.$selectedDetent.animation()
        )
        .interactiveDismissDisabled()
        .presentationBackgroundInteraction(.enabled)
        .sheet(item: self.$model.destination.settings) { model in
          NavigationStack {
            SettingsView(model: model)
          }
        }
        #if os(iOS)
          .fullScreenCover(item: self.$model.destination.mountainDetail) { model in
            NavigationStack {
              MountainDetailView(model: model)
              .dismissable()
            }
            .background(.background)
          }
        #else
          .sheet(item: self.$model.destination.mountainDetail) { model in
            NavigationStack {
              MountainDetailView(model: model)
              .dismissable()
            }
          }
        #endif
        NavigationStack {
          self.sheetContent(AnyView(erasing: content))
        }
      }
  }
}

// MARK: - MountainsMapView

private struct MountainsListMapView: View {
  let model: MountainsListModel

  var body: some View {
    ZStack {
      Map(initialPosition: .userLocation(fallback: .automatic)) {
        UserAnnotation()
        ForEach(self.model.mountains) { page in
          ForEach(page.value.mountains) { mountain in
            Annotation(mountain: mountain) {
              self.model.mountainDetailInvoked(for: mountain.id)
            }
          }
        }
      }
    }
    .mapControls {
      MapUserLocationButton()
      MapCompass()
      MapScaleView()
    }
  }
}

// MARK: - MountainsListSheetContentView

private struct MountainsListSheetContentView: View {
  @Bindable var model: MountainsListModel
  let isFullScreen: Bool

  @State private var hasScrolled = false

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 15, pinnedViews: [.sectionHeaders]) {
        Section {
          ForEach(self.model.mountains) { page in
            ForEach(page.value.mountains) { mountain in
              Button {
                self.model.mountainDetailInvoked(for: mountain.id)
              } label: {
                MountainCardView(mountain: mountain)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal)
          MountainsListSheetLoadingView(model: self.model)
            .padding()
        } header: {
          MountainsListSheetHeaderView(model: self.model, isFullScreen: self.isFullScreen)
            .padding()
            .background(.regularMaterial.opacity(self.hasScrolled ? 1 : 0))
        }
      }
    }
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y > geometry.contentInsets.top
    } action: { _, hasScrolled in
      withAnimation {
        self.hasScrolled = hasScrolled
      }
    }
  }
}

// MARK: - MountainsListSheetHeaderView

private struct MountainsListSheetHeaderView: View {
  @Bindable var model: MountainsListModel
  let isFullScreen: Bool

  @ScaledMetric private var profileHeight = 45

  var body: some View {
    VStack {
      HStack(alignment: .center) {
        MountainsListSearchFieldView(
          text: self.$model.searchText,
          isFullScreen: self.isFullScreen
        )

        Button {
          self.model.settingsInvoked()
        } label: {
          ProfileCircleView(height: self.profileHeight)
            .accessibilityLabel("Profile")
        }
        .buttonStyle(.plain)
      }
      .padding(.vertical)

      Picker("Category", selection: self.$model.category) {
        Text("Recommended").tag(Mountain.Search.Category.recommended)
        Text("Planned Climbs").tag(Mountain.Search.Category.planned)
      }
      .pickerStyle(.segmented)
    }
  }
}

// MARK: - MountainsListSheetLoadingView

private struct MountainsListSheetLoadingView: View {
  @Environment(\.colorScheme) private var colorScheme

  @SharedReader(.networkStatus) private var networkStatus = .connected

  let model: MountainsListModel

  var body: some View {
    Group {
      if self.model.$mountains.isLoading {
        SpinnerView()
      } else if let error = self.model.$mountains.error {
        VStack {
          Text("An Error Occurred")
            .font(.title3.bold())
          if self.networkStatus != .connected {
            Text("Check your internet connection and try again.")
          } else {
            Text(error.localizedDescription)
          }
          Button("Retry") {
            Task { try await self.model.$mountains.fetchNextPage() }
          }
          .bold()
          .buttonStyle(.borderedProminent)
          .tint(self.colorScheme == .light ? .primary : .secondaryBackground)
        }
      } else if !self.model.$mountains.hasNextPage {
        Text("You've reached the end of the list.")
      } else {
        SpinnerView()
          .onAppear {
            Task { try await self.model.$mountains.fetchNextPage() }
          }
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }
}

// MARK: - MountainsListSearchFieldView

private struct MountainsListSearchFieldView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Binding var text: String
  let isFullScreen: Bool

  @ScaledMetric private var height = 45

  var body: some View {
    HStack(alignment: .center) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(text: self.$text.animation()) {
        Text("Find Mountains")
          .fontWeight(.semibold)
      }

      Spacer()

      if !self.text.isEmpty {
        Button {
          self.text = ""
        } label: {
          Image(systemName: "xmark")
            .foregroundStyle(.secondary)
            .accessibilityLabel("Clear")
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal)
    .frame(height: self.height)
    .background(
      self.colorScheme == .dark
        ? AnyShapeStyle(Color.secondaryBackground)
        : AnyShapeStyle(.background.opacity(self.isFullScreen ? 1 : 0.5))
    )
    .clipShape(Capsule())
    .shadow(color: Color.black.opacity(self.isFullScreen ? 0.15 : 0), radius: 15, y: 10)
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = try! canIClimbDatabase()

    let searcher = Mountain.MockSearcher()
    searcher.results[.recommended(page: 0)] = .success(
      Mountain.SearchResult(mountains: [.mock1], hasNextPage: false)
    )
    searcher.results[.planned(page: 0)] = .success(
      Mountain.SearchResult(mountains: [.mock2], hasNextPage: false)
    )
    $0[Mountain.SearcherKey.self] = searcher
  }

  let model = MountainsListModel()
  MountainsListView(model: model) { $0 }
}
