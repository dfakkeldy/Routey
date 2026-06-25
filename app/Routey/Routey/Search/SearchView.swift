import SQLiteData
import SwiftUI
import RouteyModel
import RouteySearch

struct SearchView: View {
  @Dependency(\.defaultDatabase) private var database
  @State private var query = ""
  @State private var results = [SearchHit]()
  @State private var lastSearchedQuery = ""
  @State private var errorMessage = ""

  var body: some View {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    Group {
      if trimmedQuery.isEmpty {
        ContentUnavailableView(
          "Search Route",
          systemImage: "magnifyingglass",
          description: Text("Enter a civic number, street, occupant, stop, or tag.")
        )
      } else if !errorMessage.isEmpty {
        ContentUnavailableView(
          "Couldn't Search",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else if lastSearchedQuery != trimmedQuery {
        List {}
      } else if lastSearchedQuery == trimmedQuery && results.isEmpty {
        ContentUnavailableView("Not on this route.", systemImage: "magnifyingglass")
      } else {
        List {
          ForEach(results, id: \.address.id) { hit in
            SearchResultRow(hit: hit)
          }
        }
      }
    }
    .navigationTitle("Search")
    .searchable(
      text: $query,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Civic, street, name, or tag"
    )
    .task(id: query) {
      await search(query)
    }
  }

  private func search(_ query: String) async {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedQuery.isEmpty else {
      results = []
      lastSearchedQuery = ""
      errorMessage = ""
      return
    }

    results = []
    lastSearchedQuery = ""
    errorMessage = ""

    do {
      try await Task.sleep(for: .milliseconds(250))
      try Task.checkCancellation()

      results = try SearchService(database: database).search(trimmedQuery)
      lastSearchedQuery = trimmedQuery
      errorMessage = ""
    } catch is CancellationError {
    } catch {
      results = []
      lastSearchedQuery = trimmedQuery
      errorMessage = error.localizedDescription
    }
  }
}

private struct SearchResultRow: View {
  let hit: SearchHit

  var body: some View {
    VStack(alignment: .leading) {
      Text(addressTitle)
        .bold()

      if !locatorText.isEmpty {
        Label(locatorText, systemImage: "mappin.and.ellipse")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if !hit.sharedCivics.isEmpty {
        Text("also: \(sharedCivicsText)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if !hit.tags.isEmpty {
        SearchTagChipRow(tags: hit.tags)
      }
    }
  }

  private var addressTitle: String {
    [
      hit.address.civicNumber.map { $0.formatted(.number.grouping(.never)) },
      hit.address.street.isEmpty ? nil : hit.address.street,
    ]
    .compactMap(\.self)
    .joined(separator: " ")
  }

  private var locatorText: String {
    [
      hit.stopNickname.isEmpty ? nil : hit.stopNickname,
      hit.moduleName,
      hit.compartmentLabel,
      hit.tieOut.isEmpty ? nil : hit.tieOut,
    ]
    .compactMap(\.self)
    .joined(separator: " · ")
  }

  private var sharedCivicsText: String {
    hit.sharedCivics
      .map { $0.formatted(.number.grouping(.never)) }
      .joined(separator: ", ")
  }
}

private struct SearchTagChipRow: View {
  let tags: [SearchTag]

  var body: some View {
    ScrollView(.horizontal) {
      HStack {
        ForEach(tags) { tag in
          SearchTagChip(tag: tag)
        }
      }
    }
    .scrollIndicators(.hidden)
  }
}

private struct SearchTagChip: View {
  let tag: SearchTag

  var body: some View {
    Label(tag.name, systemImage: tag.isWarning ? "exclamationmark.triangle.fill" : "tag")
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundStyle(tag.isWarning ? .red : .secondary)
      .background(tag.isWarning ? .red.opacity(0.12) : .secondary.opacity(0.12), in: .capsule)
  }
}

#Preview {
  NavigationStack {
    SearchView()
  }
}
