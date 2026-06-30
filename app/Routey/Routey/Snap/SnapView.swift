import RouteyModel
import SQLiteData
import SwiftUI

struct SnapView: View {
  let route: Route
  let onClose: () -> Void

  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @State private var model: SnapViewModel?

  var body: some View {
    NavigationStack {
      Group {
        if let model {
          content(for: model)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Snap Parcel")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        Button("Done", action: onClose)
      }
    }
    .task {
      if model == nil {
        model = SnapViewModel(route: route, database: database)
      }
    }
  }

  @ViewBuilder
  private func content(for model: SnapViewModel) -> some View {
    switch model.phase {
    case .capturing:
      #if os(iOS)
      CameraCaptureView(
        onCapture: { data in Task { await model.handleCapturedImage(data) } },
        onError: { _ in model.reset() }
      )
      .ignoresSafeArea(edges: .bottom)
      #else
      ContentUnavailableView(
        "Use a device",
        systemImage: "camera",
        description: Text("Snap a label on an iPhone.")
      )
      #endif
    case .reading:
      ProgressView("Reading label…")
    case .result(let result):
      SnapResultView(result: result, model: model)
    case .added(let signatureCount):
      SnapAddedView(signatureCount: signatureCount, model: model)
        .task { await RouteySyncing.sendChanges(reason: "parcel snapped", using: syncEngine) }
    case .failed(let message):
      ContentUnavailableView {
        Label("Couldn't snap", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { model.reset() }
      }
    }
  }
}

private struct SnapAddedView: View {
  let signatureCount: Int
  let model: SnapViewModel

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.largeTitle)
        .foregroundStyle(.green)
      Text("Parcel added")
        .font(.title2).bold()
      Text("Signatures today: \(signatureCount)")
        .foregroundStyle(.secondary)
      HStack {
        Button("Undo", systemImage: "arrow.uturn.backward") {
          Task { await model.undoLastAdd() }
        }
        Button("Snap another", systemImage: "camera") {
          model.reset()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
  }
}
