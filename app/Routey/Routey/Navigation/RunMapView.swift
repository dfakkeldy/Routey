import MapKit
import RouteyModel
import SQLiteData
import SwiftUI

struct RunMapView: View {
  let runID: TodaysRun.ID
  @Dependency(\.defaultDatabase) private var database
  @State private var snapshot = RunMapSnapshot.empty
  @State private var isLoading = true
  @State private var errorMessage = ""
  @State private var isShowingError = false

  var body: some View {
    Group {
      if isLoading {
        ProgressView()
      } else if snapshot.stops.isEmpty {
        ContentUnavailableView(
          "No mapped stops",
          systemImage: "map",
          description: Text("Resolve coordinates to preview this run on a map.")
        )
      } else {
        RunMapContent(snapshot: snapshot)
      }
    }
    .navigationTitle("Run Map")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: runID) {
      loadSnapshot()
    }
    .alert("Couldn't Load Map", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func loadSnapshot() {
    do {
      snapshot = try RunMapSnapshot.load(runID: runID, in: database)
      isLoading = false
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      isLoading = false
    }
  }
}

private struct RunMapContent: View {
  let snapshot: RunMapSnapshot
  @State private var position: MapCameraPosition = .automatic
  @State private var selectedStopID: RunMapStop.ID?

  private var selectedStop: RunMapStop? {
    snapshot.stops.first { $0.id == selectedStopID } ?? snapshot.stops.first
  }

  var body: some View {
    Map(position: $position) {
      if snapshot.stops.count > 1 {
        MapPolyline(coordinates: snapshot.stops.map(\.coordinate))
          .stroke(.blue, lineWidth: 4)
      }

      ForEach(snapshot.stops) { stop in
        Annotation(stop.title, coordinate: stop.coordinate, anchor: .bottom) {
          Button {
            selectedStopID = stop.id
          } label: {
            RunMapMarker(order: stop.order, isSelected: selectedStopID == stop.id)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Stop \(stop.order.formatted(.number.grouping(.never)))")
        }
      }
    }
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .safeAreaInset(edge: .bottom) {
      if let selectedStop {
        RunMapStopPanel(stop: selectedStop, unresolvedCount: snapshot.unresolvedCount)
      }
    }
    .onChange(of: snapshot.stops) { _, _ in
      selectedStopID = snapshot.stops.first?.id
      position = .automatic
    }
    .onAppear {
      selectedStopID = snapshot.stops.first?.id
    }
  }
}

private struct RunMapMarker: View {
  let order: Int
  let isSelected: Bool

  var body: some View {
    Text(order, format: .number.grouping(.never))
      .font(.caption)
      .bold()
      .foregroundStyle(.white)
      .frame(width: isSelected ? 36 : 30, height: isSelected ? 36 : 30)
      .background(isSelected ? Color.accentColor : .blue, in: .circle)
      .shadow(radius: isSelected ? 3 : 1)
  }
}

private struct RunMapStopPanel: View {
  let stop: RunMapStop
  let unresolvedCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Stop \(stop.order.formatted(.number.grouping(.never)))")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        if unresolvedCount > 0 {
          Label("\(unresolvedCount.formatted(.number)) unmapped", systemImage: "mappin.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Text(stop.title)
        .font(.headline)

      if !stop.subtitle.isEmpty {
        Text(stop.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Button("Open in Maps", systemImage: "map") {
        AppleMapsHandoff.openDestination(title: stop.title, coordinate: stop.coordinate)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial)
  }
}

#Preview {
  RunMapContent(
    snapshot: RunMapSnapshot(
      stops: [
        RunMapStop(
          id: UUID(),
          title: "Parcel Stop 1",
          subtitle: "Case slot A",
          order: 1,
          coordinate: CLLocationCoordinate2D(latitude: 45.0000, longitude: -63.0000)
        ),
        RunMapStop(
          id: UUID(),
          title: "Parcel Stop 2",
          subtitle: "Case slot B",
          order: 2,
          coordinate: CLLocationCoordinate2D(latitude: 45.0100, longitude: -63.0150)
        ),
        RunMapStop(
          id: UUID(),
          title: "Parcel Stop 3",
          subtitle: "Case slot C",
          order: 3,
          coordinate: CLLocationCoordinate2D(latitude: 45.0210, longitude: -63.0050)
        ),
      ],
      unresolvedCount: 1,
      totalDistance: 4_200
    )
  )
}
