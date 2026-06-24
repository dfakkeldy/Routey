import SQLiteData
import SwiftUI
import UniformTypeIdentifiers
import RouteyDomain
import RouteyImport

struct ImportRouteView: View {
  @Dependency(\.defaultDatabase) private var database
  @Environment(\.dismiss) private var dismiss
  @State private var routeName = ""
  @State private var routeText = ""
  @State private var parseResult = ParseResult()
  @State private var isImportingFile = false
  @State private var errorMessage = ""
  @State private var isShowingError = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Route Name") {
          TextField("Imported route", text: $routeName)
        }

        Section("Route Text") {
          TextEditor(text: $routeText)
            .monospaced()
            .frame(minHeight: 160)

          Button("Choose File", systemImage: "doc") {
            isImportingFile = true
          }
        }

        Section("Preview") {
          LabeledContent("Stops", value: parseResult.stops.count.formatted())
          LabeledContent("Skipped", value: parseResult.skipped.count.formatted())

          ForEach(parseResult.skipped, id: \.line) { row in
            Text("Line \(row.line): \(row.reason)")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }
      .navigationTitle("Import Route")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Import", action: importRoute)
            .disabled(parseResult.stops.isEmpty)
        }
      }
      .fileImporter(
        isPresented: $isImportingFile,
        allowedContentTypes: [.commaSeparatedText, .plainText, .text]
      ) { result in
        loadFile(result)
      }
      .alert("Couldn't Import Route", isPresented: $isShowingError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage)
      }
      .onChange(of: routeText, initial: true) { _, newValue in
        parseResult = RouteParser.parse(newValue)
      }
    }
  }

  private func importRoute() {
    do {
      _ = try RouteImporter.importRoute(
        named: routeName.trimmingCharacters(in: .whitespaces).isEmpty ? "Imported route" : routeName,
        from: parseResult,
        into: database
      )
      dismiss()
    } catch {
      show(error)
    }
  }

  private func loadFile(_ result: Result<URL, any Error>) {
    do {
      let url = try result.get()
      let canAccess = url.startAccessingSecurityScopedResource()
      defer {
        if canAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      routeText = try String(contentsOf: url, encoding: .utf8)
      if routeName.trimmingCharacters(in: .whitespaces).isEmpty {
        routeName = url.deletingPathExtension().lastPathComponent
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
