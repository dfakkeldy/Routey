import SQLiteData
import SwiftUI
import RouteyDomain
import RouteyModel

struct AddressEditorView: View {
  let address: Address
  @Dependency(\.defaultDatabase) private var database
  @State private var civicNumberText: String
  @State private var street: String
  @State private var occupantName: String
  @State private var notes: String
  @State private var errorMessage = ""
  @State private var isShowingError = false

  init(address: Address) {
    self.address = address
    _civicNumberText = State(
      initialValue: address.civicNumber.map { $0.formatted(.number.grouping(.never)) } ?? ""
    )
    _street = State(initialValue: address.street)
    _occupantName = State(initialValue: address.occupantName ?? "")
    _notes = State(initialValue: address.notes)
  }

  var body: some View {
    Form {
      Section("Address") {
        TextField("Civic number", text: $civicNumberText)
          .keyboardType(.numberPad)
        TextField("Street", text: $street)
        TextField("Occupant", text: $occupantName)
        TextField("Notes", text: $notes, axis: .vertical)
          .lineLimit(3...6)
      }

      TagPickerView(addressID: address.id)
    }
    .navigationTitle(street.isEmpty ? "Address" : street)
    .toolbar {
      Button("Save", systemImage: "checkmark", action: save)
        .disabled(!canSave)
    }
    .alert("Couldn't Save Address", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var canSave: Bool {
    parsedCivicNumber != nil || civicNumberText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var parsedCivicNumber: Int? {
    let trimmed = civicNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return Int(trimmed)
  }

  private func save() {
    do {
      try RouteEditing.updateAddress(
        address.id,
        civicNumber: parsedCivicNumber,
        street: street,
        occupantName: optionalText(occupantName),
        notes: notes,
        in: database
      )
    } catch {
      show(error)
    }
  }

  private func optionalText(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func show(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}
