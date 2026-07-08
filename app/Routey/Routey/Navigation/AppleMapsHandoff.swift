import CoreLocation
import MapKit

enum AppleMapsHandoff {
  static func openDestination(title: String, coordinate: CLLocationCoordinate2D) {
    let placemark = MKPlacemark(coordinate: coordinate)
    let mapItem = MKMapItem(placemark: placemark)
    mapItem.name = title
    mapItem.openInMaps(
      launchOptions: [
        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
      ]
    )
  }
}
