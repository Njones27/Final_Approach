import Foundation

/// The grid of small cells that a shown photo's place is kept by.
///
/// A photo shown away from the listed spots is shown at a place, which is
/// one cell of this grid. The app sends the middle of the cell in place of
/// where the photo was taken, so the exact position never leaves the
/// phone. The backend cuts the map the same way and names each cell the
/// same way, such as `n33640w84428`.
public struct PlaceGrid: Equatable, Sendable {
    /// How many cells one degree is cut into. 1,000 makes a cell about 110
    /// meters tall.
    public let cellsPerDegree: Int

    /// Returns nil for a grid with no cells.
    public init?(cellsPerDegree: Int) {
        guard cellsPerDegree >= 1 else { return nil }
        self.cellsPerDegree = cellsPerDegree
    }

    /// The id of the cell a point falls in.
    public func placeID(at point: GeoPoint) -> String {
        let latitude = Self.cell(point.latitude, cellsPerDegree)
        let longitude = wrapped(Self.cell(point.longitude, cellsPerDegree))
        return "\(latitude < 0 ? "s" : "n")\(abs(latitude))\(longitude < 0 ? "w" : "e")\(abs(longitude))"
    }

    /// The middle of the cell a point falls in. This is what is sent and
    /// shown in place of the point itself.
    public func cellCenter(of point: GeoPoint) -> GeoPoint {
        let per = Double(cellsPerDegree)
        let latitude = Double(Self.cell(point.latitude, cellsPerDegree)) / per
        let longitude = Double(wrapped(Self.cell(point.longitude, cellsPerDegree))) / per
        // A cell's middle is on the map whenever the point is.
        return GeoPoint(latitude: latitude, longitude: longitude) ?? point
    }

    /// The middle of a place's cell, or nil for an id that names no cell.
    /// A cell has one id, so a second spelling of it gives nil too.
    public func center(ofPlaceID id: String) -> GeoPoint? {
        var rest = Substring(id)
        guard let northOrSouth = rest.popFirst(), northOrSouth == "n" || northOrSouth == "s" else { return nil }
        let latitudeDigits = rest.prefix(while: Self.isDigit)
        rest = rest.dropFirst(latitudeDigits.count)
        guard let eastOrWest = rest.popFirst(), eastOrWest == "e" || eastOrWest == "w" else { return nil }
        guard let latitudeCell = Self.number(in: latitudeDigits), let longitudeCell = Self.number(in: rest) else {
            return nil
        }

        let per = Double(cellsPerDegree)
        let latitude = Double(northOrSouth == "s" ? -latitudeCell : latitudeCell) / per
        let longitude = Double(eastOrWest == "w" ? -longitudeCell : longitudeCell) / per
        guard let center = GeoPoint(latitude: latitude, longitude: longitude), placeID(at: center) == id else {
            return nil
        }
        return center
    }

    /// About how many meters tall one cell is, as a round number to say to
    /// a person. 1,000 cells in a degree gives 100.
    public var roughCellMeters: Int {
        // One degree of latitude is about 111 kilometers everywhere.
        let exact = 111_320.0 / Double(cellsPerDegree)
        guard exact >= 1 else { return 1 }
        let magnitude = pow(10, (log10(exact)).rounded(.down))
        return Int((exact / magnitude).rounded() * magnitude)
    }

    /// The cell a number of degrees falls in, rounded the way the backend
    /// rounds it, with a half going up.
    private static func cell(_ degrees: Double, _ cellsPerDegree: Int) -> Int {
        Int((degrees * Double(cellsPerDegree) + 0.5).rounded(.down))
    }

    /// Brings a count of cells east of Greenwich back inside one turn of
    /// the globe, so the two sides of the 180° meridian are one cell.
    private func wrapped(_ cell: Int) -> Int {
        let turn = 360 * cellsPerDegree
        let half = turn / 2
        return ((cell + half) % turn + turn) % turn - half
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// A count written in plain digits with no zero in front, or nil.
    private static func number(in digits: Substring) -> Int? {
        guard !digits.isEmpty, digits.count <= 8, digits.allSatisfy(isDigit) else { return nil }
        guard digits == "0" || digits.first != "0" else { return nil }
        return Int(digits)
    }
}
