import Foundation

/// A point on the map.
public struct GeoPoint: Equatable, Hashable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    /// Returns nil when either value is outside the range of a real place.
    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The distance to another point in meters, along the surface of a round
    /// Earth. It is exact enough to pick the nearest spot.
    public func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let startLatitude = latitude * .pi / 180
        let endLatitude = other.latitude * .pi / 180
        let latitudeChange = endLatitude - startLatitude
        let longitudeChange = (other.longitude - longitude) * .pi / 180
        // The haversine formula.
        let latitudeTerm = sin(latitudeChange / 2) * sin(latitudeChange / 2)
        let longitudeTerm = sin(longitudeChange / 2) * sin(longitudeChange / 2)
        let haversine = latitudeTerm + cos(startLatitude) * cos(endLatitude) * longitudeTerm
        return earthRadius * 2 * asin(min(1, sqrt(haversine)))
    }

    /// The compass direction to another point, in degrees from 0 up to 360,
    /// where 0 is north and 90 is east. It is the direction to set out in,
    /// which is exact enough for an aircraft a few kilometers away.
    public func bearing(to other: GeoPoint) -> Double {
        let startLatitude = latitude * .pi / 180
        let endLatitude = other.latitude * .pi / 180
        let longitudeChange = (other.longitude - longitude) * .pi / 180
        let east = sin(longitudeChange) * cos(endLatitude)
        let northNear = cos(startLatitude) * sin(endLatitude)
        let northFar = sin(startLatitude) * cos(endLatitude) * cos(longitudeChange)
        let degrees = atan2(east, northNear - northFar) * 180 / .pi
        return Compass.normalized(degrees)
    }
}

/// Helpers for compass directions in degrees.
public enum Compass {
    /// Brings a direction into the range from 0 up to 360.
    public static func normalized(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        let turned = wrapped < 0 ? wrapped + 360 : wrapped
        // A tiny negative number rounds up to a full turn, which is north.
        return turned >= 360 ? 0 : turned
    }

    /// The smallest turn between two directions, from 0 to 180 degrees.
    public static func difference(_ first: Double, _ second: Double) -> Double {
        let turn = abs(normalized(first) - normalized(second))
        return turn > 180 ? 360 - turn : turn
    }
}

/// A place a photo can be linked to, such as a spotting location.
public struct Landmark: Equatable, Sendable {
    public let id: String
    public let point: GeoPoint

    public init(id: String, point: GeoPoint) {
        self.id = id
        self.point = point
    }
}

public enum NearestLandmark {
    /// The landmark closest to a point, or nil when none lies within
    /// `maximumDistance` meters. The first of two equally close landmarks
    /// wins.
    ///
    /// The distance is data, so how close a photo must be to count as taken
    /// from a spot can be tuned without a release.
    public static func find(
        to point: GeoPoint,
        among landmarks: [Landmark],
        within maximumDistance: Double
    ) -> (landmark: Landmark, distance: Double)? {
        var nearest: (landmark: Landmark, distance: Double)?
        for landmark in landmarks {
            let distance = point.distance(to: landmark.point)
            guard distance <= maximumDistance else { continue }
            if let current = nearest, current.distance <= distance { continue }
            nearest = (landmark, distance)
        }
        return nearest
    }
}

/// The smallest box of latitude and longitude that holds a set of points,
/// used to frame them on a map.
public struct GeoBounds: Equatable, Sendable {
    public let center: GeoPoint
    /// The height of the box in degrees of latitude.
    public let latitudeSpan: Double
    /// The width of the box in degrees of longitude.
    public let longitudeSpan: Double

    /// Returns nil when there are no points. Points on both sides of the
    /// 180° meridian are framed the long way round, which no listed airport
    /// needs yet.
    public init?(points: [GeoPoint]) {
        guard let first = points.first else { return nil }
        var south = first.latitude
        var north = first.latitude
        var west = first.longitude
        var east = first.longitude
        for point in points.dropFirst() {
            south = min(south, point.latitude)
            north = max(north, point.latitude)
            west = min(west, point.longitude)
            east = max(east, point.longitude)
        }
        guard let center = GeoPoint(latitude: (south + north) / 2, longitude: (west + east) / 2) else {
            return nil
        }
        self.center = center
        latitudeSpan = north - south
        longitudeSpan = east - west
    }

    /// The spans grown by `padding`, where 0.4 adds 40 percent, and never
    /// smaller than `minimumSpan` degrees. A single point would otherwise
    /// have no span to show.
    public func framedSpans(padding: Double, minimumSpan: Double) -> (latitude: Double, longitude: Double) {
        let scale = 1 + max(padding, 0)
        return (
            min(max(latitudeSpan * scale, minimumSpan), 180),
            min(max(longitudeSpan * scale, minimumSpan), 360)
        )
    }
}
