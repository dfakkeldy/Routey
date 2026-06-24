import SQLiteData
import SwiftUI
import RouteyDomain
import RouteyModel

struct TagPickerView: View {
  let addressID: Address.ID
  @Dependency(\.defaultDatabase) private var database
  @FetchAll private var allTags: [Tag]
  @FetchAll private var selectedTags: [Tag]
  @State private var newTagName = ""
  @State private var newTagIsWarning = false
  @State private var errorMessage = ""
  @State private var isShowingError = false

  init(addressID: Address.ID) {
    self.addressID = addressID
    _allTags = FetchAll(Tag.order { $0.name })
    _selectedTags = FetchAll(
      Tag
        .where { tag in
          AddressTag
            .where {
              $0.addressID.eq(#bind(addressID))
                && $0.tagID.eq(tag.id)
            }
            .exists()
        }
        .order { $0.name }
    )
  }

  var body: some View {
    Section("Tags") {
      if allTags.isEmpty {
        Text("No tags")
          .foregroundStyle(.secondary)
      } else {
        ForEach(allTags) { tag in
          Toggle(isOn: binding(for: tag)) {
            Label(tag.name, systemImage: tag.isWarning ? "exclamationmark.triangle" : "tag")
          }
        }
      }

      TextField("New tag", text: $newTagName)
      Toggle("Warning", isOn: $newTagIsWarning)
      Button("Add Tag", systemImage: "plus", action: addTag)
        .disabled(trimmedNewTagName.isEmpty)
    }
    .alert("Couldn't Edit Tags", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var selectedTagIDs: Set<Tag.ID> {
    Set(selectedTags.map(\.id))
  }

  private var trimmedNewTagName: String {
    newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func binding(for tag: Tag) -> Binding<Bool> {
    Binding {
      selectedTagIDs.contains(tag.id)
    } set: { isSelected in
      set(tag, isSelected: isSelected)
    }
  }

  private func addTag() {
    do {
      try RouteEditing.attachTag(
        named: trimmedNewTagName,
        toAddress: addressID,
        isWarning: newTagIsWarning,
        in: database
      )
      newTagName = ""
      newTagIsWarning = false
    } catch {
      show(error)
    }
  }

  private func set(_ tag: Tag, isSelected: Bool) {
    do {
      if isSelected {
        try RouteEditing.attachTag(
          named: tag.name,
          toAddress: addressID,
          isWarning: tag.isWarning,
          in: database
        )
      } else {
        try RouteEditing.detachTag(tag.id, fromAddress: addressID, in: database)
      }
    } catch {
      show(error)
    }
  }

  private func show(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}
