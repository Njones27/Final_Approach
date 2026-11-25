import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// Spots. The client for the spot routes, the list of spots in the
/// collection, which spot's page or place on the map a posted photo is
/// shown at, the photos a spot's page or a place holds, and what the map
/// and the ranked list show around a point.
@MainActor
final class SpotsTests {
    private let base = URL(string: "https://api.example.test")!
    private let posted = Date(timeIntervalSince1970: 1_800_000_000)
    private let directory: URL
    private let store: FilePhotoStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "final-approach-spots-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FilePhotoStore(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    /// A photo taken at the sample south approach spot. Its spot shows
    /// unless it is made private.
    private func photo(
        _ id: String = "imported-1",
        isPrivate: Bool = false,
        isBlocked: Bool = false,
        spotID: String? = "atl-south-approach",
        coordinate: Coordinate? = Coordinate(latitude: 33.6220, longitude: -84.3995),
        camera: CameraSettings? = nil
    ) -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "N8642E",
            isRegistrationBlocked: isBlocked,
            airline: "Southwest Airlines",
            activity: "",
            camera: camera,
            loggedAt: posted,
            captureCoordinate: coordinate,
            spotID: spotID,
            isLocationUndisclosed: isPrivate,
            status: .logged
        )
    }

    private var southApproach: SpotShowing {
        SpotShowing(spotID: "atl-south-approach", aircraftType: "Boeing 737-800", airline: "Southwest Airlines")
    }

    /// Somewhere far from every sample spot. It falls in the cell named
    /// by `awayPlaceID`, well inside its edges.
    private var away: Coordinate? {
        Coordinate(latitude: 34.2001, longitude: -84.9002)
    }

    private let awayPlaceID = "n34200w84900"

    /// A photo taken away from every listed spot, with its location
    /// showing unless it is made private.
    private func awayPhoto(isPrivate: Bool = false, camera: CameraSettings? = nil) -> SpottedPhoto {
        photo(isPrivate: isPrivate, spotID: nil, coordinate: away, camera: camera)
    }

    private var awayPlace: SpotShowing {
        SpotShowing(placeID: awayPlaceID, aircraftType: "Boeing 737-800", airline: "Southwest Airlines")
    }

    /// The settings of a photo taken with a long lens, with the gear named.
    private var longLens: CameraSettings {
        CameraSettings(
            cameraMake: "Canon",
            cameraModel: "Canon EOS R5",
            lensModel: "RF100-500mm F4.5-7.1 L IS USM",
            focalLength: 400,
            aperture: 5.6,
            exposureTime: 0.001,
            iso: 200
        )
    }

    private var longLensShown: ShownCamera {
        ShownCamera(focalLength: 400, aperture: 5.6, exposureTime: 0.001, iso: 200)
    }

    private func point(_ latitude: Double, _ longitude: Double) throws -> Coordinate {
        try #require(Coordinate(latitude: latitude, longitude: longitude))
    }

    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func tinyJPEG() throws -> Data {
        try #require(tinyImage().jpegData(compressionQuality: 0.8))
    }

    private func standing(votes: Int = 0, score: Int? = nil) -> PostStanding {
        PostStanding(
            postedAt: posted,
            closesAt: posted.addingTimeInterval(72 * 3600),
            voteCount: votes,
            finalScore: score
        )
    }

    // MARK: The client for the spot routes

    private func spotClient(_ transport: ScriptedTransport) -> HTTPSpotBackend {
        HTTPSpotBackend(baseURL: base, transport: transport, accessToken: { "token-1" })
    }

    private func postClient(_ transport: ScriptedTransport) -> HTTPPostBackend {
        HTTPPostBackend(
            baseURL: base,
            transport: transport,
            placeGrid: SampleData.placeGrid,
            accessToken: { "token-1" }
        )
    }

    private func spotAnswer(_ id: String, latitude: Double, notes: Bool) -> [String: Any] {
        var answer: [String: Any] = [
            "id": id,
            "name": "South approach",
            "summary": "Arrivals pass low from the east.",
            "latitude": latitude,
            "longitude": -84.399,
        ]
        if notes {
            answer["accessNotes"] = "Park on the gravel."
            answer["localRules"] = "Keep the gate clear."
            answer["runwayNotes"] = "Looks at the south runways."
        }
        return answer
    }

    private func photoAnswer(_ id: String, score: Int, type: String? = nil, airline: String? = nil) -> [String: Any] {
        var answer: [String: Any] = [
            "id": id,
            "imageURL": "https://images.example.test/\(id)?signature=abc",
            "score": score,
        ]
        if let type {
            answer["aircraftType"] = type
        }
        if let airline {
            answer["airline"] = airline
        }
        return answer
    }

    @Test func theListOfSpotsIsReadAsTheSignedInUser() async throws {
        let atlanta: [String: Any] = [
            "code": "ATL",
            "city": "Atlanta",
            "latitude": 33.6407,
            "longitude": -84.4277,
            "spots": [
                spotAnswer("atl-south-approach", latitude: 33.6215, notes: true),
                spotAnswer("atl-no-notes", latitude: 33.63, notes: false),
                // A spot that is not a real place cannot go on the map.
                spotAnswer("atl-nowhere", latitude: 133, notes: false),
            ],
        ]
        let transport = ScriptedTransport([.init(body: try json(["airports": [atlanta]]))])

        let airports = try await spotClient(transport).airports()

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/spots")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(airports.count == 1)
        let airport = try #require(airports.first)
        #expect(airport.id == "ATL")
        #expect(airport.displayName == "Atlanta, ATL")
        let ids = airport.spots.map { $0.id }
        #expect(ids == ["atl-south-approach", "atl-no-notes"])
        let first = try #require(airport.spots.first)
        #expect(first.name == "South approach")
        #expect(first.accessNotes == "Park on the gravel.")
        #expect(first.localRules == "Keep the gate clear.")
        #expect(first.runwayNotes == "Looks at the south runways.")
        let second = try #require(airport.spots.last)
        #expect(second.accessNotes.isEmpty)
    }

    @Test func aSpotSaysWhichWayItLooksOnlyWhenTheDirectionIsOnTheCompass() async throws {
        var west = spotAnswer("atl-west", latitude: 33.62, notes: false)
        west["viewBearing"] = 270
        var wrong = spotAnswer("atl-wrong", latitude: 33.63, notes: false)
        wrong["viewBearing"] = 400
        let plain = spotAnswer("atl-plain", latitude: 33.64, notes: false)
        let atlanta: [String: Any] = [
            "code": "ATL",
            "city": "Atlanta",
            "latitude": 33.6407,
            "longitude": -84.4277,
            "spots": [west, wrong, plain],
        ]
        let transport = ScriptedTransport([.init(body: try json(["airports": [atlanta]]))])

        let airports = try await spotClient(transport).airports()

        let spots = try #require(airports.first?.spots)
        let bearings = spots.map { $0.viewBearing }
        #expect(bearings == [270, nil, nil])
    }

    @Test func aSpotsPhotosComeWithTheirGradeAndWhatTheOwnerShows() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "photos": [
                    photoAnswer("post-1", score: 91, type: "Boeing VC-25A", airline: "US Air Force"),
                    photoAnswer("post-2", score: 140),
                ],
                "imageLinkExpiresInSeconds": 300,
            ])),
        ])

        let photos = try await spotClient(transport).photos(atSpotID: "atl-south-approach")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/spots/atl-south-approach/photos")
        #expect(photos.count == 2)
        let best = try #require(photos.first)
        #expect(best.id == "post-1")
        #expect(best.imageURL.absoluteString == "https://images.example.test/post-1?signature=abc")
        #expect(best.score == 91)
        #expect(best.aircraftType == "Boeing VC-25A")
        #expect(best.airline == "US Air Force")
        // A photo whose owner shows no aircraft has none, and a grade is
        // kept on the scale.
        let other = try #require(photos.last)
        #expect(other.aircraftType == nil)
        #expect(other.airline == nil)
        #expect(other.score == 100)
    }

    @Test func aSpotThatIsNotListedHasNoPage() async throws {
        let transport = ScriptedTransport([
            .init(status: 404, body: try json(["message": "This spot is not listed.", "code": "unknownSpot"])),
        ])

        await #expect(throws: PhotoBackendError.unknownSpot) {
            _ = try await self.spotClient(transport).photos(atSpotID: "gone")
        }
    }

    @Test func anImageIsFetchedWithNoTokenAndALinkThatRanOutGivesNone() async throws {
        let link = try #require(URL(string: "https://images.example.test/post-1?signature=abc"))
        let transport = ScriptedTransport([.init(body: Data([1, 2, 3])), .init(status: 403)])
        let client = spotClient(transport)

        let image = try await client.image(from: link)
        let expired = try await client.image(from: link)

        #expect(image == Data([1, 2, 3]))
        #expect(expired == nil)
        let request = try #require(transport.requests.first)
        // The link carries its own permission.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func theMapAsksWhatIsShownAroundAPointToTwoDecimals() async throws {
        var withCamera = photoAnswer("post-2", score: 84, type: "F-22 Raptor")
        withCamera["camera"] = ["focalLength": 400, "aperture": 5.6, "exposureTime": 0.001, "iso": 200] as [String: Any]
        let shownSpot: [String: Any] = [
            "spotID": "atl-south-approach",
            "photoCount": 4,
            "bestPhoto": photoAnswer("post-1", score: 91, type: "Boeing VC-25A", airline: "US Air Force"),
        ]
        let shownPlace: [String: Any] = [
            "id": "n33631w84450",
            "latitude": 33.631,
            "longitude": -84.45,
            "photoCount": 2,
            "bestPhoto": withCamera,
        ]
        // A place that is not on the map cannot have a pin.
        let nowhere: [String: Any] = [
            "id": "n133000w84450",
            "latitude": 133,
            "longitude": -84.45,
            "photoCount": 1,
            "bestPhoto": photoAnswer("post-3", score: 50),
        ]
        let transport = ScriptedTransport([
            .init(body: try json([
                "spots": [shownSpot],
                "places": [shownPlace, nowhere],
                "imageLinkExpiresInSeconds": 300,
            ])),
        ])
        let middle = try point(33.64074, -84.42771)

        let around = try await spotClient(transport).shown(around: middle)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        // Two decimals is about a kilometer, which is all the backend
        // needs to know about where the user is looking.
        #expect(request.url?.absoluteString == "https://api.example.test/places?latitude=33.64&longitude=-84.43")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(around.spots.count == 1)
        let spot = try #require(around.spots.first)
        #expect(spot.id == "atl-south-approach")
        #expect(spot.photoCount == 4)
        #expect(spot.bestPhoto.id == "post-1")
        #expect(spot.bestPhoto.score == 91)
        #expect(spot.bestPhoto.camera == nil)
        #expect(around.places.count == 1)
        let place = try #require(around.places.first)
        #expect(place.id == "n33631w84450")
        #expect(place.coordinate == Coordinate(latitude: 33.631, longitude: -84.45))
        #expect(place.photoCount == 2)
        #expect(place.bestPhoto.aircraftType == "F-22 Raptor")
        #expect(place.bestPhoto.camera == longLensShown)
    }

    @Test func aPointIsWrittenWithTwoDecimals() {
        #expect(HTTPSpotBackend.degrees(33.64074) == "33.64")
        #expect(HTTPSpotBackend.degrees(-84.42771) == "-84.43")
        #expect(HTTPSpotBackend.degrees(7) == "7.00")
        #expect(HTTPSpotBackend.degrees(-0.05) == "-0.05")
        // A point just west of Greenwich is not written as minus zero.
        #expect(HTTPSpotBackend.degrees(-0.004) == "0.00")
        #expect(HTTPSpotBackend.degrees(179.996) == "180.00")
    }

    @Test func aPlacesPhotosAreReadByItsID() async throws {
        var withCamera = photoAnswer("post-2", score: 84)
        withCamera["camera"] = ["focalLength": 400, "aperture": 5.6, "exposureTime": 0.001, "iso": 200] as [String: Any]
        let transport = ScriptedTransport([
            .init(body: try json([
                "photos": [withCamera, photoAnswer("post-4", score: 60)],
                "imageLinkExpiresInSeconds": 300,
            ])),
        ])

        let photos = try await spotClient(transport).photos(atPlaceID: "n33631w84450")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/places/n33631w84450/photos")
        let ids = photos.map { $0.id }
        #expect(ids == ["post-2", "post-4"])
        #expect(photos.first?.camera == longLensShown)
        // A photo whose owner shows no settings has none.
        #expect(photos.last?.camera == nil)
    }

    // MARK: The client for showing a photo at a spot

    @Test func showingAPhotoSendsTheSpotAndTheWordsBesideItAndNothingElse() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "photoID": "imported-1",
                "shownAt": ["spotID": "atl-south-approach", "aircraftType": "Boeing 737-800"],
            ])),
        ])
        let showing = SpotShowing(spotID: "atl-south-approach", aircraftType: "Boeing 737-800")

        let kept = try await postClient(transport).show(photoID: "imported-1", at: showing)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.example.test/posts/imported-1/spot")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        let body = try #require(request.httpBody)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
        // No position and no registration is sent, and an airline that is
        // not shown is left out.
        #expect(sent == ["spotID": "atl-south-approach", "aircraftType": "Boeing 737-800"])
        #expect(kept == showing)
    }

    @Test func anAnswerAboutAnotherPhotoIsNotTrusted() async throws {
        let transport = ScriptedTransport([
            .init(body: try json(["photoID": "imported-2", "shownAt": ["spotID": "atl-south-approach"]])),
        ])

        await #expect(throws: PhotoBackendError.unreadableAnswer) {
            _ = try await self.postClient(transport).show(
                photoID: "imported-1",
                at: SpotShowing(spotID: "atl-south-approach")
            )
        }
    }

    @Test func showingAPhotoAtAPlaceSendsTheMiddleOfItsCellAndTheCameraSettings() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "photoID": "imported-1",
                "shownAt": ["placeID": awayPlaceID, "camera": ["focalLength": 400, "iso": 200]] as [String: Any],
            ])),
        ])
        let showing = SpotShowing(placeID: awayPlaceID, camera: ShownCamera(focalLength: 400, iso: 200))

        let kept = try await postClient(transport).show(photoID: "imported-1", at: showing)

        let body = try #require(transport.requests.first?.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let sent = try #require(object)
        // The place's id is not sent, and neither is a spot.
        #expect(sent.keys.sorted() == ["camera", "place"])
        // The position is the middle of the cell, which is all the place's
        // id can give. Where the photo was taken never reaches this client.
        let place = sent["place"] as? [String: Double]
        #expect(place?.keys.sorted() == ["latitude", "longitude"])
        #expect(abs((place?["latitude"] ?? 0) - 34.2) < 1e-9)
        #expect(abs((place?["longitude"] ?? 0) + 84.9) < 1e-9)
        let camera = sent["camera"] as? [String: Double]
        #expect(camera == ["focalLength": 400, "iso": 200])
        #expect(kept == showing)
    }

    @Test func aPlaceThatNamesNoCellIsNotSent() async throws {
        let transport = ScriptedTransport([])

        await #expect(throws: PhotoBackendError.unknownSpot) {
            _ = try await self.postClient(transport).show(
                photoID: "imported-1",
                at: SpotShowing(placeID: "behind-the-fence")
            )
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func anAnswerThatNamesNowhereIsNotTrusted() async throws {
        let transport = ScriptedTransport([
            .init(body: try json(["photoID": "imported-1", "shownAt": ["airline": "Southwest Airlines"]])),
        ])

        await #expect(throws: PhotoBackendError.unreadableAnswer) {
            _ = try await self.postClient(transport).show(
                photoID: "imported-1",
                at: SpotShowing(spotID: "atl-south-approach")
            )
        }
    }

    @Test func aPhotoThatIsNotPostedOrASpotThatIsNotListedIsRefused() async throws {
        let transport = ScriptedTransport([
            .init(status: 409, body: try json(["message": "Post the photo first.", "code": "notPosted"])),
            .init(status: 404, body: try json(["message": "This spot is not listed.", "code": "unknownSpot"])),
        ])
        let showing = SpotShowing(spotID: "atl-south-approach")

        await #expect(throws: PhotoBackendError.notPosted) {
            _ = try await self.postClient(transport).show(photoID: "imported-1", at: showing)
        }
        await #expect(throws: PhotoBackendError.unknownSpot) {
            _ = try await self.postClient(transport).show(photoID: "imported-1", at: showing)
        }
    }

    @Test func takingAPhotoOffASpotSendsOnlyItsID() async throws {
        let transport = ScriptedTransport([.init(status: 204)])

        try await postClient(transport).hide(photoID: "imported-1")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.example.test/posts/imported-1/spot")
        #expect(request.httpBody == nil)
    }

    @Test func aListingSaysWhichPageEachPhotoIsOn() async throws {
        let shown: [String: Any] = [
            "photoID": "imported-1",
            "postedAt": "2027-01-15T08:00:00.000Z",
            "closesAt": "2027-01-18T08:00:00.000Z",
            "voteCount": 6,
            "status": "final",
            "score": 74,
            "shownAt": ["spotID": "atl-south-approach", "airline": "Southwest Airlines"],
        ]
        let notShown: [String: Any] = [
            "photoID": "imported-2",
            "postedAt": "2027-01-15T08:00:00.000Z",
            "closesAt": "2027-01-18T08:00:00.000Z",
            "voteCount": 0,
            "status": "voting",
        ]
        let transport = ScriptedTransport([.init(body: try json(["posts": [shown, notShown], "minVotes": 5]))])

        let listing = try await postClient(transport).listPosts()

        #expect(listing.standings.count == 2)
        #expect(listing.showings == [
            "imported-1": SpotShowing(spotID: "atl-south-approach", airline: "Southwest Airlines"),
        ])
    }

    @Test func aListingReadsAPlaceAndLeavesOutSomewhereItDoesNotKnow() async throws {
        func post(_ photoID: String, shownAt: [String: Any]) -> [String: Any] {
            [
                "photoID": photoID,
                "postedAt": "2027-01-15T08:00:00.000Z",
                "closesAt": "2027-01-18T08:00:00.000Z",
                "voteCount": 0,
                "status": "voting",
                "shownAt": shownAt,
            ]
        }
        let atPlace = post("imported-1", shownAt: [
            "placeID": awayPlaceID,
            "aircraftType": "Boeing 737-800",
            "camera": ["focalLength": 400, "aperture": 5.6, "exposureTime": 0.001, "iso": 200],
        ])
        let somewhereNew = post("imported-2", shownAt: ["regionID": "north-georgia"])
        let transport = ScriptedTransport([.init(body: try json(["posts": [atPlace, somewhereNew], "minVotes": 5]))])

        let listing = try await postClient(transport).listPosts()

        // Both posts are read. Only the one this version can place is
        // said to be shown.
        #expect(listing.standings.count == 2)
        #expect(listing.showings == [
            "imported-1": SpotShowing(placeID: awayPlaceID, aircraftType: "Boeing 737-800", camera: longLensShown),
        ])
    }

    @Test func aShowingSavedBeforePlacesExistedStillReads() throws {
        let old = Data(#"{"spotID":"atl-south-approach","airline":"Southwest Airlines"}"#.utf8)
        let read = try JSONDecoder().decode(SpotShowing.self, from: old)
        #expect(read == SpotShowing(spotID: "atl-south-approach", airline: "Southwest Airlines"))

        let place = SpotShowing(placeID: awayPlaceID, aircraftType: "Boeing 737-800", camera: longLensShown)
        let saved = try JSONEncoder().encode(place)
        let reread = try JSONDecoder().decode(SpotShowing.self, from: saved)
        #expect(reread == place)
    }

    // MARK: Where a photo may be shown

    @Test func aPhotoWithItsSpotShowingMayGoOnThatSpotsPage() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo()) == southApproach)
    }

    @Test func aPrivatePhotoGoesOnNoPage() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo(isPrivate: true)) == nil)
        // Its owner still sees which spot it was taken from.
        #expect(model.listedSpot(for: photo(isPrivate: true))?.id == "atl-south-approach")
    }

    @Test func aSamplePhotoGoesOnNoPage() throws {
        let model = SampleData.model()
        let sample = try #require(model.photo(id: "b737-n823ak"))

        #expect(model.spotShowing(for: sample) == nil)
    }

    @Test func aBlockedAircraftShowsNoTypeAndNoAirline() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo(isBlocked: true)) == SpotShowing(spotID: "atl-south-approach"))
    }

    @Test func aPhotoTakenAwayFromEverySpotMayGoOnTheMapAtItsPlace() {
        let model = SampleData.model()

        // It is not near a listed spot, so its owner sees none for it.
        #expect(model.listedSpot(for: awayPhoto()) == nil)
        #expect(model.spotShowing(for: awayPhoto()) == awayPlace)
    }

    @Test func everyPhotoTakenInOneCellIsShownAtTheSamePlace() {
        let model = SampleData.model()
        let corner = photo(spotID: nil, coordinate: Coordinate(latitude: 34.2004, longitude: -84.8996))

        #expect(model.spotShowing(for: corner)?.placeID == awayPlaceID)
        #expect(model.spotShowing(for: awayPhoto())?.placeID == awayPlaceID)
    }

    @Test func aPrivatePhotoTakenAwayFromEverySpotIsShownNowhere() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: awayPhoto(isPrivate: true)) == nil)
    }

    @Test func aPhotoWithNoSpotAndNoLocationIsShownNowhere() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo(spotID: nil, coordinate: nil)) == nil)
    }

    @Test func theCameraSettingsAreShownWithoutTheGear() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo(camera: longLens))?.camera == longLensShown)
        #expect(model.spotShowing(for: awayPhoto(camera: longLens))?.camera == longLensShown)
        // A blocked aircraft is not named, and its settings name nothing.
        #expect(model.spotShowing(for: photo(isBlocked: true, camera: longLens))
            == SpotShowing(spotID: "atl-south-approach", camera: longLensShown))
        // A photo that names only its gear shows no settings.
        let gearOnly = CameraSettings(cameraModel: "Canon EOS R5")
        #expect(model.spotShowing(for: photo(camera: gearOnly))?.camera == nil)
    }

    @Test func aLineTheBackendWouldRefuseIsLeftOut() {
        let model = SampleData.model()
        let long = SpottedPhoto(
            id: "imported-1",
            imageName: nil,
            aircraftType: String(repeating: "a", count: model.shownTextMaxLength + 1),
            registration: "",
            airline: "  ",
            activity: "",
            spotID: "atl-south-approach",
            status: .logged
        )

        #expect(model.spotShowing(for: long) == SpotShowing(spotID: "atl-south-approach"))
    }

    @Test func aPhotoLoggedBeforeItsSpotWasListedFindsItByWhereItWasTaken() {
        // A build with a backend starts with no spots.
        let model = SampleData.model(airports: [])
        #expect(model.airports.isEmpty)
        #expect(model.listedSpot(for: photo(spotID: nil)) == nil)
        // With no spot listed near it, the photo would go on the map.
        #expect(model.spotShowing(for: photo(spotID: nil))?.spotID == nil)
        #expect(model.spotShowing(for: photo(spotID: nil))?.placeID != nil)

        model.takeSpotCatalog(SampleData.airports)

        #expect(model.listedSpot(for: photo(spotID: nil))?.id == "atl-south-approach")
        #expect(model.spotShowing(for: photo(spotID: nil)) == southApproach)
    }

    @Test func aSpotThatIsNoLongerListedGivesWayToTheNearestOne() {
        let model = SampleData.model()

        #expect(model.listedSpot(for: photo(spotID: "atl-closed-spot"))?.id == "atl-south-approach")
    }

    @Test func onlyAPostedPhotoIsOnAPage() {
        let model = SampleData.model()
        model.add(photo("imported-1"))
        model.add(photo("imported-2"))

        model.takePostListing(PostListing(
            standings: ["imported-1": standing()],
            showings: ["imported-1": southApproach, "imported-2": southApproach],
            minimumVotes: 5
        ))

        #expect(model.spotShowings == ["imported-1": southApproach])

        // A page set for a photo with no post is not kept.
        model.takeSpotShowing(southApproach, forPhotoID: "imported-2")
        #expect(model.spotShowings == ["imported-1": southApproach])
    }

    @Test func aListingThatNamesNoPageTakesThePhotoOffItsPage() {
        let model = SampleData.model()
        model.add(photo())
        model.takePostListing(PostListing(
            standings: ["imported-1": standing()],
            showings: ["imported-1": southApproach],
            minimumVotes: 5
        ))

        model.takePostListing(PostListing(standings: ["imported-1": standing()], minimumVotes: 5))

        #expect(model.spotShowings.isEmpty)
    }

    @Test func deletingAPhotoOrTheAccountForgetsItsPage() {
        let model = SampleData.model()
        model.add(photo("imported-1"))
        model.add(photo("imported-2"))
        model.takePostListing(PostListing(
            standings: ["imported-1": standing(), "imported-2": standing()],
            showings: ["imported-1": southApproach, "imported-2": southApproach],
            minimumVotes: 5
        ))

        model.deletePhoto(id: "imported-1")
        #expect(model.spotShowings == ["imported-2": southApproach])

        model.deleteAccountAndPhotos()
        #expect(model.spotShowings.isEmpty)
    }

    @Test func aPageIsStillThereWhenTheAppReopens() {
        let model = SampleData.model(store: store)
        model.add(photo(), image: tinyImage())
        model.takePostListing(PostListing(
            standings: ["imported-1": standing(votes: 6, score: 74)],
            showings: ["imported-1": southApproach],
            minimumVotes: 5
        ))

        let reopened = SampleData.model(store: store)

        #expect(reopened.spotShowings == ["imported-1": southApproach])
    }

    @Test func aLibrarySavedBeforeSpotPagesExistedStillOpens() throws {
        let old = Data(#"{"photos":[],"removedSampleIDs":[]}"#.utf8)

        let library = try JSONDecoder().decode(StoredLibrary.self, from: old)

        #expect(library.spotShowings == nil)
    }

    // MARK: Showing a posted photo at its spot

    private func appleToken(for userID: String = "apple-user-1") -> String {
        let payload = Data(#"{"sub":"\#(userID)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    private func signedInSession() async throws -> AccountSession {
        let session = AccountSession(identity: SampleIdentityService(), store: MemorySessionStore())
        try await session.signIn(identityToken: appleToken())
        return session
    }

    private struct Rig {
        let sync: SyncCoordinator
        let photos: SamplePhotoBackend
        let posts: SamplePostBackend
    }

    /// A coordinator on in-memory backends, signed in.
    private func makeRig() async throws -> Rig {
        let photos = SamplePhotoBackend()
        let posted = self.posted
        let posts = SamplePostBackend(photos: photos, now: { posted })
        let sync = SyncCoordinator(
            session: try await signedInSession(),
            backend: photos,
            posts: posts,
            pacing: SyncPacing(),
            sleep: { _ in }
        )
        return Rig(sync: sync, photos: photos, posts: posts)
    }

    @Test func postingAPhotoWithItsSpotShowingPutsItOnTheSpotsPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(rig.posts.showings == ["imported-1": southApproach])
        #expect(phone.spotShowings == ["imported-1": southApproach])
    }

    @Test func postingAPrivatePhotoPutsItOnNoPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(isPrivate: true), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(asked == .cannotShow)
        #expect(rig.posts.showCount == 0)
        #expect(phone.spotShowings.isEmpty)
    }

    @Test func aPostStandsWhenItsPageCouldNotBeReached() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        rig.posts.nextShowFailure = .unavailable(status: 503)

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(phone.postStandings["imported-1"] != nil)
        #expect(phone.spotShowings.isEmpty)

        // A sync puts nothing on a page by itself. The owner asks again.
        await rig.sync.sync(on: phone)
        #expect(rig.posts.showCount == 0)

        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)
        #expect(asked == .done)
        #expect(phone.spotShowings == ["imported-1": southApproach])
    }

    @Test func theOwnerCanTakeAPhotoOffItsPageAndPutItBack() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)

        let takenOff = await rig.sync.takeOffSpot(photoID: "imported-1", on: phone)

        #expect(takenOff == .done)
        #expect(rig.posts.showings.isEmpty)
        #expect(phone.spotShowings.isEmpty)
        // The post and its standing stay.
        #expect(phone.postStandings["imported-1"] != nil)

        // It stays off through a sync, until the owner puts it back.
        await rig.sync.sync(on: phone)
        #expect(rig.posts.showings.isEmpty)

        let putBack = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)
        #expect(putBack == .done)
        #expect(rig.posts.showings == ["imported-1": southApproach])
    }

    @Test func aPhotoThatIsNotPostedGoesOnNoPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())

        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(asked == .cannotShow)
        #expect(rig.posts.showCount == 0)
    }

    @Test func postingAPhotoTakenAwayFromEverySpotPutsItOnTheMapAtItsPlace() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(awayPhoto(camera: longLens), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        var wanted = awayPlace
        wanted.camera = longLensShown
        #expect(outcome == .posted)
        #expect(rig.posts.showings == ["imported-1": wanted])
        #expect(phone.spotShowings == ["imported-1": wanted])
    }

    @Test func postingAPrivatePhotoTakenAwayFromEverySpotShowsItNowhere() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(awayPhoto(isPrivate: true), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(asked == .cannotShow)
        #expect(rig.posts.showCount == 0)
        #expect(phone.spotShowings.isEmpty)
    }

    @Test func aPhotoWithNoSpotAndNoLocationHasNowhereToBeShown() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model(airports: [])
        phone.add(photo(spotID: nil, coordinate: nil), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(asked == .spotNotListed)
        #expect(rig.posts.showCount == 0)
    }

    @Test func theOwnerCanTakeAPhotoOffTheMapAndPutItBack() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(awayPhoto(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)

        let takenOff = await rig.sync.takeOffSpot(photoID: "imported-1", on: phone)
        #expect(takenOff == .done)
        #expect(rig.posts.showings.isEmpty)
        #expect(phone.spotShowings.isEmpty)

        let putBack = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)
        #expect(putBack == .done)
        #expect(rig.posts.showings == ["imported-1": awayPlace])
    }

    @Test func anEditToTheAircraftKeepsThePlaceAndTheSettingsAsTheyWereShown() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(awayPhoto(camera: longLens), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)
        // The backend holds the photo as it was shown before camera
        // settings were shown, with none beside it.
        _ = try await rig.posts.show(photoID: "imported-1", at: awayPlace)

        phone.updateDetails(
            forPhotoID: "imported-1",
            aircraftType: "Boeing 737-700",
            registration: nil,
            airline: ""
        )
        await rig.sync.sync(on: phone)

        // The words change. The place stays, and no settings are added
        // that the owner did not choose to show.
        let wanted = SpotShowing(placeID: awayPlaceID, aircraftType: "Boeing 737-700")
        #expect(rig.posts.showings == ["imported-1": wanted])
        #expect(phone.spotShowings == ["imported-1": wanted])
    }

    @Test func aPrivatePhotoFoundOnTheMapIsTakenOff() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(awayPhoto(isPrivate: true), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)
        // The backend holds a place for it, as a mistake elsewhere could
        // leave one.
        _ = try await rig.posts.show(photoID: "imported-1", at: awayPlace)

        await rig.sync.sync(on: phone)

        #expect(rig.posts.showings.isEmpty)
        #expect(phone.spotShowings.isEmpty)
    }

    @Test func aSpotTheBackendNoLongerListsTakesNoPhoto() async throws {
        let rig = try await makeRig()
        rig.posts.listedSpotIDs = ["atl-north-deck"]
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(asked == .spotNotListed)
        #expect(phone.spotShowings.isEmpty)
    }

    @Test func nothingIsShownWhileNoOneIsSignedIn() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)
        await rig.sync.signOut()

        let shown = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)
        let takenOff = await rig.sync.takeOffSpot(photoID: "imported-1", on: phone)

        #expect(shown == .signInNeeded)
        #expect(takenOff == .signInNeeded)
        #expect(rig.posts.showings == ["imported-1": southApproach])
    }

    @Test func anEditToTheAircraftReachesItsPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)

        phone.updateDetails(
            forPhotoID: "imported-1",
            aircraftType: "Boeing 737-700",
            registration: nil,
            airline: ""
        )
        await rig.sync.sync(on: phone)

        let wanted = SpotShowing(spotID: "atl-south-approach", aircraftType: "Boeing 737-700")
        #expect(rig.posts.showings == ["imported-1": wanted])
        #expect(phone.spotShowings == ["imported-1": wanted])

        // A sync with nothing new sends nothing more.
        let sent = rig.posts.showCount
        await rig.sync.sync(on: phone)
        #expect(rig.posts.showCount == sent)
    }

    @Test func aPrivatePhotoFoundOnAPageIsTakenOff() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(isPrivate: true), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)
        // The backend holds a page for it, as a mistake elsewhere could
        // leave one.
        _ = try await rig.posts.show(photoID: "imported-1", at: southApproach)

        await rig.sync.sync(on: phone)

        #expect(rig.posts.showings.isEmpty)
        #expect(phone.spotShowings.isEmpty)
    }

    // MARK: The spots model

    private func shownPhoto(_ id: String, score: Int) throws -> SampleSpotBackend.Photo {
        SampleSpotBackend.Photo(
            id: id,
            image: try tinyJPEG(),
            score: score,
            aircraftType: "Boeing 737-800",
            airline: "Southwest Airlines"
        )
    }

    /// A backend that lists the sample spots, with two photos on one page.
    private func spotBackend() throws -> SampleSpotBackend {
        SampleSpotBackend(
            airports: SampleData.airports,
            photos: [
                "atl-south-approach": [
                    try shownPhoto("post-low", score: 61),
                    try shownPhoto("post-high", score: 88),
                ],
            ]
        )
    }

    @Test func theListOfSpotsReachesTheCollection() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        #expect(spots.phase == .idle)

        await spots.refresh(on: model)

        #expect(spots.phase == .loaded)
        #expect(model.airports == SampleData.airports)
        #expect(model.spot(id: "atl-south-approach")?.name == "South approach")
    }

    @Test func noSpotsAreAskedForWhileNoOneIsSignedIn() async throws {
        let backend = try spotBackend()
        let session = AccountSession(identity: SampleIdentityService(), store: MemorySessionStore())
        let spots = SpotsModel(session: session, backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])

        await spots.refresh(on: model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        #expect(spots.phase == .signInNeeded)
        #expect(backend.catalogCount == 0)
        #expect(backend.pageCounts.isEmpty)
        #expect(spots.pages.isEmpty)
        #expect(model.airports.isEmpty)
    }

    @Test func aBuildWithNoBackendShowsItsSpotsWithNoSignIn() async throws {
        let backend = try spotBackend()
        let session = AccountSession(identity: nil, store: MemorySessionStore())
        let spots = SpotsModel(session: session, backend: backend, needsSignIn: false)
        let model = SampleData.model()

        await spots.refresh(on: model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        #expect(spots.phase == .loaded)
        #expect(spots.pages["atl-south-approach"]?.photos.count == 2)
    }

    @Test func aListThatCannotBeFetchedLeavesTheOneInHand() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        await spots.refresh(on: model)

        backend.catalogFailure = .unavailable(status: 503)
        await spots.refresh(on: model)

        #expect(spots.phase == .loaded)
        #expect(model.airports == SampleData.airports)
    }

    @Test func aFirstListThatCannotBeFetchedSaysSoAndIsTriedAgain() async throws {
        let backend = try spotBackend()
        backend.catalogFailure = .unavailable(status: 503)
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])

        await spots.refresh(on: model)
        #expect(spots.phase == .couldNotLoad)
        #expect(model.airports.isEmpty)

        backend.catalogFailure = nil
        await spots.refresh(on: model)
        #expect(spots.phase == .loaded)
        #expect(model.airports == SampleData.airports)
    }

    @Test func aSpotAddedOnTheBackendShowsUpOnTheNextRefresh() async throws {
        let backend = SampleSpotBackend(airports: [])
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        await spots.refresh(on: model)
        #expect(spots.phase == .loaded)
        #expect(model.airports.isEmpty)

        backend.list(SampleData.airports)
        await spots.refresh(on: model)

        #expect(model.airports == SampleData.airports)
    }

    @Test func aSpotsPhotosComeBestFirst() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)

        await spots.loadPhotos(atSpotID: "atl-south-approach")
        await spots.loadPhotos(atSpotID: "atl-west-road")

        let page = try #require(spots.pages["atl-south-approach"])
        #expect(page.phase == .loaded)
        let ids = page.photos.map { $0.id }
        #expect(ids == ["post-high", "post-low"])
        let best = try #require(page.photos.first)
        #expect(best.score == 88)
        #expect(best.aircraftType == "Boeing 737-800")
        // A spot nobody has shown a photo at has an empty page.
        #expect(spots.pages["atl-west-road"] == SpotsModel.Page(phase: .loaded))
    }

    @Test func photosThatCannotBeLoadedLeaveTheOnesInHand() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        backend.pageFailure = .unavailable(status: 503)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        await spots.loadPhotos(atSpotID: "atl-north-deck")

        let page = try #require(spots.pages["atl-south-approach"])
        #expect(page.phase == .couldNotLoad)
        #expect(page.photos.count == 2)
        #expect(spots.pages["atl-north-deck"] == SpotsModel.Page(phase: .couldNotLoad))
    }

    @Test func aSmallCopyOfAPhotoIsKeptOnlyWhileItIsOnAPage() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        let page = try #require(spots.pages["atl-south-approach"])
        let best = try #require(page.photos.first)

        let image = await spots.thumbnail(for: best)

        #expect(image != nil)
        #expect(spots.hasThumbnail(forPhotoID: "post-high"))

        // Its owner deletes it, and the page is asked for again.
        backend.remove(photoID: "post-high")
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        #expect(!spots.hasThumbnail(forPhotoID: "post-high"))
        #expect(spots.pages["atl-south-approach"]?.photos.count == 1)
    }

    @Test func aPhotoWhoseLinkRanOutHasNoImage() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let link = try #require(URL(string: "https://images.example.test/gone"))
        let gone = SpotPhoto(id: "gone", imageURL: link, score: 70)

        let image = await spots.thumbnail(for: gone)

        #expect(image == nil)
        #expect(!spots.hasThumbnail(forPhotoID: "gone"))
    }

    @Test func deletingAPhotoClearsTheCopiesOfSpotPhotos() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model()
        spots.follow(model)
        model.add(photo())
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        let page = try #require(spots.pages["atl-south-approach"])
        let best = try #require(page.photos.first)
        _ = await spots.thumbnail(for: best)
        #expect(spots.hasThumbnail(forPhotoID: "post-high"))

        // One of the photos on a page may be the user's own, so a delete
        // leaves no copy behind.
        model.deletePhoto(id: "imported-1")

        #expect(spots.pages.isEmpty)
        #expect(!spots.hasThumbnail(forPhotoID: "post-high"))
    }

    @Test func deletingTheAccountClearsTheCopiesOfSpotPhotos() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model()
        spots.follow(model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        let page = try #require(spots.pages["atl-south-approach"])
        let best = try #require(page.photos.first)
        _ = await spots.thumbnail(for: best)

        model.deleteAccountAndPhotos()

        #expect(spots.pages.isEmpty)
        #expect(!spots.hasThumbnail(forPhotoID: "post-high"))
    }

    @Test func signingOutForgetsThePhotosAndKeepsTheSpots() async throws {
        let backend = try spotBackend()
        let session = try await signedInSession()
        let spots = SpotsModel(session: session, backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        await spots.refresh(on: model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        #expect(spots.pages.count == 1)

        await session.signOut()
        await spots.refresh(on: model)

        #expect(spots.phase == .signInNeeded)
        #expect(spots.pages.isEmpty)
        // The list stays, so a photo logged while signed out still finds
        // its spot.
        #expect(model.airports == SampleData.airports)
    }

    @Test func aLargeImageIsMadeSmallAndASmallOneIsLeftAlone() {
        #expect(SpotsModel.fitted(CGSize(width: 6000, height: 4000), within: 1200) == CGSize(width: 1200, height: 800))
        #expect(SpotsModel.fitted(CGSize(width: 3000, height: 4500), within: 1200) == CGSize(width: 800, height: 1200))
        #expect(SpotsModel.fitted(CGSize(width: 900, height: 600), within: 1200) == CGSize(width: 900, height: 600))
    }

    // MARK: What is shown on the map

    private let westPlaceID = "n33631w84450"
    private let northPlaceID = "n33664w84401"
    private let seattlePlaceID = "n47463w122320"

    /// The sample spots with two photos on one page, two places near
    /// Atlanta, and one near Seattle. One place has two photos.
    private func placeBackend() throws -> SampleSpotBackend {
        let backend = try spotBackend()
        var best = try shownPhoto("place-high", score: 84)
        best.camera = longLensShown
        let west = try point(33.631, -84.45)
        backend.show(try shownPhoto("place-low", score: 55), atPlaceID: westPlaceID, middle: west)
        backend.show(best, atPlaceID: westPlaceID, middle: west)
        backend.show(
            try shownPhoto("place-north", score: 79),
            atPlaceID: northPlaceID,
            middle: try point(33.664, -84.401)
        )
        backend.show(
            try shownPhoto("place-seattle", score: 74),
            atPlaceID: seattlePlaceID,
            middle: try point(47.463, -122.32)
        )
        return backend
    }

    @Test func theMapIsToldWhatIsShownNearItsMiddle() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let atlanta = try point(33.6407, -84.4277)
        #expect(spots.around == nil)
        #expect(spots.needsShown(around: atlanta))

        await spots.loadShown(around: atlanta)

        let around = try #require(spots.around)
        #expect(around.phase == .loaded)
        #expect(around.center == atlanta)
        // Only a spot with photos is in the answer.
        let spotIDs = around.shown.spots.map { $0.id }
        #expect(spotIDs == ["atl-south-approach"])
        let spot = try #require(around.shown.spots.first)
        #expect(spot.photoCount == 2)
        #expect(spot.bestPhoto.id == "post-high")
        // The place near Seattle is too far away to be in it.
        let placeIDs = around.shown.places.map { $0.id }
        #expect(placeIDs == [westPlaceID, northPlaceID])
        let place = try #require(around.shown.places.first)
        #expect(place.photoCount == 2)
        #expect(place.bestPhoto.id == "place-high")
        #expect(place.bestPhoto.camera == longLensShown)
        #expect(place.coordinate == Coordinate(latitude: 33.631, longitude: -84.45))
    }

    @Test func theMapIsAskedAgainOnlyOnceItHasMovedFarEnough() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let atlanta = try point(33.6407, -84.4277)
        let nearby = try point(33.66, -84.40)
        let seattle = try point(47.4502, -122.3088)
        await spots.loadShown(around: atlanta)

        #expect(!spots.needsShown(around: nearby))
        #expect(spots.needsShown(around: seattle))

        await spots.loadShown(around: seattle)

        #expect(backend.aroundCount == 2)
        #expect(spots.around?.center == seattle)
        let placeIDs = spots.around?.shown.places.map { $0.id }
        #expect(placeIDs == [seattlePlaceID])
        #expect(spots.needsShown(around: atlanta))
    }

    @Test func twoRequestsForTheSameViewOfTheMapAskOnce() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let atlanta = try point(33.6407, -84.4277)

        async let first: Void = spots.loadShown(around: atlanta)
        async let second: Void = spots.loadShown(around: atlanta)
        _ = await (first, second)

        #expect(backend.aroundCount == 1)
        #expect(spots.around?.center == atlanta)
    }

    @Test func aMapThatMovedOnWhileAnAnswerWasOnItsWayIsAskedAgain() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let atlanta = try point(33.6407, -84.4277)
        let seattle = try point(47.4502, -122.3088)

        async let first: Void = spots.loadShown(around: atlanta)
        async let second: Void = spots.loadShown(around: seattle)
        _ = await (first, second)

        // Whichever went second waited for the first, found the answer
        // was for somewhere far away, and asked again.
        #expect(backend.aroundCount == 2)
        #expect(spots.around?.phase == .loaded)
    }

    @Test func whatIsShownStaysWhenTheMapCannotBeAskedAgain() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let atlanta = try point(33.6407, -84.4277)
        let seattle = try point(47.4502, -122.3088)
        await spots.loadShown(around: atlanta)

        backend.aroundFailure = .unavailable(status: 503)
        await spots.loadShown(around: seattle)

        let around = try #require(spots.around)
        #expect(around.phase == .couldNotLoad)
        #expect(around.shown.places.count == 2)
        // The answer in hand is still the one for Atlanta, so the map is
        // asked again when it comes to rest near Seattle.
        #expect(around.center == atlanta)
        #expect(spots.needsShown(around: seattle))
    }

    @Test func aFirstAnswerThatCannotBeFetchedLeavesTheMapEmpty() async throws {
        let backend = try placeBackend()
        backend.aroundFailure = .unavailable(status: 503)
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let atlanta = try point(33.6407, -84.4277)

        await spots.loadShown(around: atlanta)

        #expect(spots.around == SpotsModel.Around(phase: .couldNotLoad))
        #expect(spots.needsShown(around: atlanta))
    }

    @Test func aPlacesPhotosComeBestFirstWithTheirCameraSettings() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)

        await spots.loadPhotos(atPlaceID: westPlaceID)
        await spots.loadPhotos(atPlaceID: "n10000e10000")

        let page = try #require(spots.placePages[westPlaceID])
        #expect(page.phase == .loaded)
        let ids = page.photos.map { $0.id }
        #expect(ids == ["place-high", "place-low"])
        #expect(page.photos.first?.camera == longLensShown)
        #expect(page.photos.last?.camera == nil)
        // A place nobody has shown a photo at has an empty page.
        #expect(spots.placePages["n10000e10000"] == SpotsModel.Page(phase: .loaded))
        // A place's page is kept apart from a spot's.
        #expect(spots.pages.isEmpty)
    }

    @Test func aPlacesPhotosThatCannotBeLoadedLeaveTheOnesInHand() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        await spots.loadPhotos(atPlaceID: westPlaceID)

        backend.pageFailure = .unavailable(status: 503)
        await spots.loadPhotos(atPlaceID: westPlaceID)

        let page = try #require(spots.placePages[westPlaceID])
        #expect(page.phase == .couldNotLoad)
        #expect(page.photos.count == 2)
    }

    @Test func nothingOnTheMapIsAskedForWhileNoOneIsSignedIn() async throws {
        let backend = try placeBackend()
        let session = AccountSession(identity: SampleIdentityService(), store: MemorySessionStore())
        let spots = SpotsModel(session: session, backend: backend, needsSignIn: true)

        await spots.loadShown(around: try point(33.6407, -84.4277))
        await spots.loadPhotos(atPlaceID: westPlaceID)

        #expect(backend.aroundCount == 0)
        #expect(backend.placePageCounts.isEmpty)
        #expect(spots.around == nil)
        #expect(spots.placePages.isEmpty)
    }

    @Test func aPinKeepsItsOwnSmallCopyOnlyWhileItsPhotoIsShown() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let atlanta = try point(33.6407, -84.4277)
        await spots.loadShown(around: atlanta)
        let place = try #require(spots.around?.shown.places.first)

        let image = await spots.thumbnail(for: place.bestPhoto, use: .pin)

        #expect(image != nil)
        #expect(spots.hasThumbnail(forPhotoID: "place-high", use: .pin))
        // The copy for a page is a different, larger one.
        #expect(!spots.hasThumbnail(forPhotoID: "place-high"))

        // Its owner deletes it, and the map is asked again.
        backend.remove(photoID: "place-high")
        await spots.loadShown(around: atlanta)

        #expect(!spots.hasThumbnail(forPhotoID: "place-high", use: .pin))
        let next = try #require(spots.around?.shown.places.first)
        #expect(next.bestPhoto.id == "place-low")
        #expect(next.photoCount == 1)
    }

    @Test func deletingAPhotoClearsWhatIsShownOnTheMap() async throws {
        let backend = try placeBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model()
        spots.follow(model)
        model.add(photo())
        await spots.loadShown(around: try point(33.6407, -84.4277))
        await spots.loadPhotos(atPlaceID: westPlaceID)
        let place = try #require(spots.around?.shown.places.first)
        _ = await spots.thumbnail(for: place.bestPhoto, use: .pin)
        _ = await spots.thumbnail(for: place.bestPhoto)
        #expect(spots.hasThumbnail(forPhotoID: "place-high", use: .pin))
        #expect(spots.hasThumbnail(forPhotoID: "place-high"))

        // One of the photos on the map may be the user's own, so a delete
        // leaves no copy behind.
        model.deletePhoto(id: "imported-1")

        #expect(spots.around == nil)
        #expect(spots.placePages.isEmpty)
        #expect(!spots.hasThumbnail(forPhotoID: "place-high", use: .pin))
        #expect(!spots.hasThumbnail(forPhotoID: "place-high"))
    }

    @Test func theRankedListPutsTheMostPhotosFirstAndNamesOnlyListedSpots() throws {
        let link = try #require(URL(string: "https://images.example.test/best"))
        let middle = try point(33.631, -84.45)
        let shown = ShownAround(
            spots: [
                ShownSpot(
                    id: "atl-south-approach",
                    photoCount: 2,
                    bestPhoto: SpotPhoto(id: "a", imageURL: link, score: 88)
                ),
                // A spot that is no longer listed has no name and no pin.
                ShownSpot(id: "gone", photoCount: 9, bestPhoto: SpotPhoto(id: "b", imageURL: link, score: 99)),
            ],
            places: [
                ShownPlace(
                    id: westPlaceID,
                    coordinate: middle,
                    photoCount: 5,
                    bestPhoto: SpotPhoto(id: "c", imageURL: link, score: 70)
                ),
                ShownPlace(
                    id: northPlaceID,
                    coordinate: middle,
                    photoCount: 2,
                    bestPhoto: SpotPhoto(id: "d", imageURL: link, score: 91)
                ),
            ]
        )

        let rows = RankedRow.rows(for: shown, spots: SampleData.airports.flatMap { $0.spots })

        // The most photos come first, and the better top photo breaks a
        // tie.
        let targets = rows.map { $0.target }
        #expect(targets == [.place(westPlaceID), .place(northPlaceID), .spot("atl-south-approach")])
        let titles = rows.map { $0.title }
        #expect(titles == ["Unnamed place", "Unnamed place", "South approach"])
        #expect(rows.first?.countText == "5 photos")
        #expect(RankedRow.countText(1) == "1 photo")
        #expect(RankedRow.rows(for: ShownAround(), spots: []).isEmpty)
    }

    // MARK: Wording

    @Test func theWarningBeforeAPostSaysWhereThePhotoWillBeSeen() {
        let plain = PhotoDetailView.postWarning(shownAt: nil, showsAircraft: true)
        let shown = PhotoDetailView.postWarning(shownAt: .spot(name: "South approach"), showsAircraft: true)
        let blocked = PhotoDetailView.postWarning(shownAt: .spot(name: "South approach"), showsAircraft: false)

        #expect(plain == "Voters see the photo and nothing else. They do not see your name or where it was taken. "
            + "A post cannot be taken back, but deleting the photo removes it.")
        #expect(shown.contains("it also goes on the page for South approach with its grade, aircraft type, and airline."))
        #expect(shown.contains("Your name and the registration are never shown there."))
        // A blocked aircraft is not named on the page, so the warning does
        // not say it is.
        #expect(blocked.contains("the page for South approach with its grade."))
        #expect(!blocked.contains("aircraft type"))
    }

    @Test func theWarningBeforeAPostSaysHowExactAPlaceOnTheMapIs() {
        let place = PhotoDetailView.postWarning(shownAt: .place(meters: 100), showsAircraft: true)
        let blocked = PhotoDetailView.postWarning(shownAt: .place(meters: 100), showsAircraft: false)

        #expect(place.contains("it also goes on the map with its grade, aircraft type, and airline."))
        #expect(place.contains("People see where it was taken to about 100 meters."))
        #expect(place.contains("Your name, the registration, and the exact place are never shown there."))
        #expect(blocked.contains("it also goes on the map with its grade."))
        #expect(!blocked.contains("aircraft type"))
    }

    @Test func theWarningBeforeAPostNamesTheCameraSettingsOnlyWhenTheyAreShown() {
        let with = PhotoDetailView.postWarning(
            shownAt: .spot(name: "South approach"),
            showsAircraft: true,
            showsCamera: true
        )
        let blocked = PhotoDetailView.postWarning(shownAt: .place(meters: 100), showsAircraft: false, showsCamera: true)
        let without = PhotoDetailView.postWarning(shownAt: .spot(name: "South approach"), showsAircraft: true)
        let shownNowhere = PhotoDetailView.postWarning(shownAt: nil, showsAircraft: true, showsCamera: true)

        #expect(with.contains("with its grade, aircraft type, airline, and camera settings."))
        #expect(blocked.contains("with its grade and camera settings."))
        #expect(!without.contains("camera settings"))
        // A photo that is shown nowhere shows no settings either.
        #expect(!shownNowhere.contains("camera settings"))
    }

    @Test func theOwnerIsToldWhetherAPhotoIsOnItsPageYet() {
        #expect(PhotoDetailView.shownLine(shownAt: .spot(name: "South approach"), isGraded: true)
            == "Shown on the page for South approach.")
        #expect(PhotoDetailView.shownLine(shownAt: .spot(name: "South approach"), isGraded: false)
            == "It goes on the page for South approach once it is graded.")
        #expect(PhotoDetailView.shownLine(shownAt: .spot(name: nil), isGraded: true) == "Shown on its spot's page.")
    }

    @Test func theOwnerIsToldWhetherAPhotoIsOnTheMapYet() {
        #expect(PhotoDetailView.shownLine(shownAt: .place(meters: 100), isGraded: true)
            == "Shown on the map, to about 100 meters.")
        #expect(PhotoDetailView.shownLine(shownAt: .place(meters: 100), isGraded: false)
            == "It goes on the map, to about 100 meters, once it is graded.")
    }

    @Test func theOfferSaysWhatOtherPeopleWillSee() {
        let offer = PhotoDetailView.offerLine(shownAt: .spot(name: "South approach"), showsAircraft: true)
        let blocked = PhotoDetailView.offerLine(shownAt: .spot(name: "South approach"), showsAircraft: false)

        #expect(offer.contains("its grade, aircraft type, and airline"))
        #expect(offer.contains("They never see your name or the registration."))
        #expect(!blocked.contains("aircraft type"))
    }

    @Test func theOfferForAPlaceSaysHowExactItIs() {
        let offer = PhotoDetailView.offerLine(shownAt: .place(meters: 100), showsAircraft: true, showsCamera: true)

        #expect(offer.contains("You can show this photo on the map."))
        #expect(offer.contains("its grade, aircraft type, airline, and camera settings"))
        #expect(offer.contains("where it was taken to about 100 meters"))
        #expect(offer.contains("They never see your name, the registration, or the exact place."))
    }

    @Test func theButtonsSayWhereThePhotoGoes() {
        #expect(PhotoDetailView.showTitle(shownAt: .spot(name: "South approach")) == "Show it on the spot's page")
        #expect(PhotoDetailView.takeOffTitle(shownAt: .spot(name: nil)) == "Take it off the spot's page")
        #expect(PhotoDetailView.showTitle(shownAt: .place(meters: 100)) == "Show it on the map")
        #expect(PhotoDetailView.takeOffTitle(shownAt: .place(meters: 100)) == "Take it off the map")
    }

    @Test func theChoiceMadeWhenAPhotoWasLoggedIsSaidBack() {
        #expect(PhotoDetailView.choiceLine(shownAt: .spot(name: "South approach"))
            == "You chose to show the spot. Once the photo is graded, it also goes on the page for South approach.")
        #expect(PhotoDetailView.choiceLine(shownAt: .place(meters: 100))
            == "You chose to show where this was taken. Once the photo is graded, it also goes on the map, "
            + "to about 100 meters.")
    }

    @Test func theLocationSwitchSaysHowExactAPlaceIs() {
        let detail = AddPhotoView.locationSwitchDetail(placeMeters: 100)

        #expect(detail.contains("on the map to about 100 meters"))
        #expect(detail.contains("Turn this off to keep the location private."))
    }

    @Test func everyOutcomeOfChangingAPageHasSomethingToSay() {
        let outcomes: [SpotShowOutcome] = [.done, .signInNeeded, .cannotShow, .spotNotListed, .couldNotChange]
        for outcome in outcomes {
            #expect(!PhotoDetailView.message(for: outcome).isEmpty)
        }
    }

    @Test func aSpotsPageLeavesOutANoteWithNothingWritten() throws {
        let full = try #require(SampleData.airports.first?.spots.first)
        let bare = Spot(id: "bare", name: "Bare", summary: "Nothing written.", latitude: 33.6, longitude: -84.4)

        let titles = SpotPageView.notes(for: full).map { $0.title }
        #expect(titles == ["Getting there", "Local rules", "Runways"])
        #expect(SpotPageView.notes(for: bare).isEmpty)
    }

    @Test func aPhotoOnAPageIsDescribedByWhatItsOwnerShows() throws {
        let link = try #require(URL(string: "https://images.example.test/post-1"))
        let named = SpotPhoto(
            id: "post-1",
            imageURL: link,
            score: 80,
            aircraftType: "Boeing 737-800",
            airline: "Southwest Airlines"
        )
        let unnamed = SpotPhoto(id: "post-2", imageURL: link, score: 80)

        #expect(SpotPageView.imageDescription(for: named, spotName: "South approach")
            == "Southwest Airlines Boeing 737-800, taken from South approach")
        #expect(SpotPageView.imageDescription(for: unnamed, spotName: "South approach")
            == "A photo taken from South approach")
    }

    @Test func aPhotoOnAPlacesPageIsDescribedByWhatItsOwnerShows() throws {
        let link = try #require(URL(string: "https://images.example.test/post-1"))
        let named = SpotPhoto(id: "post-1", imageURL: link, score: 80, aircraftType: "F-22 Raptor")
        let unnamed = SpotPhoto(id: "post-2", imageURL: link, score: 80)

        #expect(PlacePageView.imageDescription(for: named) == "F-22 Raptor, taken from this place")
        #expect(PlacePageView.imageDescription(for: unnamed) == "A photo taken from this place")
    }

    @Test func aPlacesPageSaysHowExactThePlaceIs() {
        let words = PlacePageView.aboutText(meters: 100)
        #expect(words.contains("to about 100 meters"))
        #expect(words.contains("no name, notes, or directions"))
    }

    // MARK: The light at a spot

    /// Midnight in Atlanta on 25 November 2026, which is 05:00 UTC.
    private let atlantaMidnight = Date(timeIntervalSince1970: 1_795_582_800)

    private func atlantaTime() throws -> Date.FormatStyle {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        return Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_US"), timeZone: zone)
    }

    private func hours(_ hours: Double) -> Date {
        atlantaMidnight.addingTimeInterval(hours * 3600)
    }

    @Test func thePageSaysWhenTheLightIsGood() throws {
        let time = try atlantaTime()
        let morning = TimeWindow(start: hours(7), end: hours(8))
        let evening = TimeWindow(start: hours(17), end: hours(17.75))
        let behind = TimeWindow(start: hours(7.25), end: hours(11.25))
        let light = DayLight(
            sunrise: hours(7.25),
            sunset: hours(17.5),
            goldenHours: [morning, evening],
            sunBehind: [behind]
        )

        let lines = SpotLight.lines(for: light, looksOneWay: true, time: time)

        let titles = lines.map { $0.title }
        #expect(titles == ["Sun behind you", "Golden hour", "Sunrise", "Sunset"])
        let texts = lines.map { $0.text }
        let behindText = "\(behind.start.formatted(time)) to \(behind.end.formatted(time))"
        let morningText = "\(morning.start.formatted(time)) to \(morning.end.formatted(time))"
        let eveningText = "\(evening.start.formatted(time)) to \(evening.end.formatted(time))"
        #expect(texts == [
            behindText,
            "\(morningText), \(eveningText)",
            hours(7.25).formatted(time),
            hours(17.5).formatted(time),
        ])
        // The times are written for the clock in Atlanta.
        #expect(behindText.hasPrefix("7:15"))
        #expect(eveningText.hasPrefix("5:00"))
    }

    @Test func aPlaceThatDoesNotSayWhichWayItLooksHasNoLineAboutTheSunBehind() throws {
        let time = try atlantaTime()
        let light = DayLight(
            sunrise: hours(7.25),
            sunset: hours(17.5),
            goldenHours: [TimeWindow(start: hours(7), end: hours(8))],
            sunBehind: []
        )

        let titles = SpotLight.lines(for: light, looksOneWay: false, time: time).map { $0.title }

        #expect(titles == ["Golden hour", "Sunrise", "Sunset"])
    }

    @Test func aDayWithNoGoodLightSaysSo() throws {
        let time = try atlantaTime()
        // Where the sun does not rise there is nothing to say but that.
        let dark = DayLight(sunrise: nil, sunset: nil, goldenHours: [], sunBehind: [])

        let lines = SpotLight.lines(for: dark, looksOneWay: true, time: time)

        #expect(lines == [
            LightLine(title: "Sun behind you", text: "Not today"),
            LightLine(title: "Golden hour", text: "Not today"),
        ])
    }

    @Test func theLightIsWorkedOutForTheDayOnTheClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        let day = SpotLight.day(holding: hours(10), in: calendar)

        #expect(day.start == atlantaMidnight)
        #expect(day.end == hours(24))
    }

    @Test func aSampleSpotThatLooksNorthHasTheSunBehindItAllDayInNovember() throws {
        let spot = try #require(SampleData.airports.first?.spots.first)
        let pin = try #require(spot.coordinate)
        #expect(spot.viewBearing == 0)

        let light = Sunlight.light(
            at: pin,
            from: atlantaMidnight,
            to: hours(24),
            viewBearing: spot.viewBearing,
            rules: .launch
        )

        let window = try #require(light.sunBehind.first)
        #expect(light.sunBehind.count == 1)
        #expect(window.start == light.sunrise)
        #expect(window.end == light.sunset)
    }
}
