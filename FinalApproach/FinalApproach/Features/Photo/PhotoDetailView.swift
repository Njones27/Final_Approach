import FinalApproachCore
import SwiftUI

/// One photo with its grade, where the grade sits on the tier scale, the
/// ideas that would lift it, and the way to post it for votes.
struct PhotoDetailView: View {
    let photoID: String

    @Environment(CollectionModel.self) private var model
    /// It is missing in a preview that does not give one, and the screen
    /// then offers no way to post.
    @Environment(SyncCoordinator.self) private var sync: SyncCoordinator?
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isEditingDetails = false
    @State private var isConfirmingPost = false
    @State private var isPosting = false
    /// Why the last try at posting did not work, or nil.
    @State private var postProblem: PostOutcome?
    /// True while the photo is being put on its spot's page or taken off.
    @State private var isChangingSpotPage = false
    /// Why the last change to the spot's page did not work, or nil.
    @State private var spotPageProblem: SpotShowOutcome?

    var body: some View {
        Group {
            if let photo = model.photo(id: photoID) {
                content(for: photo)
            } else {
                ContentUnavailableView(
                    "Photo removed",
                    systemImage: "photo",
                    description: Text("This photo is no longer in your collection.")
                )
            }
        }
        .background(Theme.ground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for photo: SpottedPhoto) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PhotoFill(image: model.image(for: photo), description: photo.imageDescription)
                    .aspectRatio(3 / 2, contentMode: .fit)

                VStack(alignment: .leading, spacing: 18) {
                    // The photo arrives with the screen. What sits under
                    // it follows, one part after another.
                    header(for: photo)
                        .revealed(order: 0)
                    gradeBlock(for: photo)
                        .revealed(order: 1)
                    feedback(for: photo)
                        .revealed(order: 2)
                    postSection(for: photo)
                        .revealed(order: 3)
                    cameraSection(for: photo)
                        .revealed(order: 4)
                    locationSection(for: photo)
                        .revealed(order: 5)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: model.image(for: photo),
                    preview: SharePreview(photo.typeTitle, image: model.image(for: photo))
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More actions", systemImage: "ellipsis") {
                    // A sample photo ships with the app and is not saved,
                    // so only a photo the user logged can be changed.
                    if !photo.isSample {
                        Button("Edit aircraft details", systemImage: "pencil") {
                            isEditingDetails = true
                        }
                    }
                    Button("Delete photo", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete photo", role: .destructive) {
                model.deletePhoto(id: photo.id)
                dismiss()
            }
        } message: {
            Text(
                model.progress(for: photo).isPosted
                    ? "The photo, its votes, and its grade are removed. Other people can no longer see it."
                    : "The photo and its grade are removed from your collection."
            )
        }
        .confirmationDialog(
            "Post this photo for votes?",
            isPresented: $isConfirmingPost,
            titleVisibility: .visible
        ) {
            Button("Post") {
                post(photo)
            }
        } message: {
            Text(
                Self.postWarning(
                    spotName: offeredSpotName(for: photo),
                    showsAircraft: !photo.hasBlockedRegistration
                )
            )
        }
        .sheet(isPresented: $isEditingDetails) {
            EditDetailsView(photo: photo)
        }
    }

    // MARK: Header

    private func header(for photo: SpottedPhoto) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(photo.typeTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.ink)
            if !photo.isTypeKnown, !photo.isSample {
                Button("Add the aircraft") {
                    isEditingDetails = true
                }
                .font(.subheadline)
                .tint(Theme.ink)
                .underline()
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let registration = photo.visibleRegistration {
                    Text(registration)
                        .font(.condensed(18, weight: .medium, relativeTo: .subheadline))
                        .tracking(1)
                        .foregroundStyle(Theme.ink)
                }
                if let operatorLine = photo.operatorLine {
                    Text(operatorLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    // MARK: Grade

    @ViewBuilder
    private func gradeBlock(for photo: SpottedPhoto) -> some View {
        switch model.progress(for: photo) {
        case let .graded(score, voteCount):
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    Text(score.scoreText)
                        .font(.condensed(78, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Grade \(score.scoreText)")
                    VStack(alignment: .leading, spacing: 3) {
                        TierLabel(tier: model.tier(for: photo))
                        Text("From \(Self.counted(voteCount, "vote"))")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                        technicalLine(for: photo)
                    }
                }
                TierScaleView(score: score, thresholds: model.thresholds)
            }
        case let .voting(votesIn, votesNeeded, hoursLeft):
            VStack(alignment: .leading, spacing: 3) {
                Text("Voting is open")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(Self.votingLine(votesIn: votesIn, votesNeeded: votesNeeded, hoursLeft: hoursLeft))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                technicalLine(for: photo)
            }
        case .logged:
            checkVerdict(for: photo)
        }
    }

    /// How the vote on a photo is going, in a sentence or two. The owner is
    /// told how many votes are in and never how they are going.
    static func votingLine(votesIn: Int, votesNeeded: Int, hoursLeft: Int) -> String {
        let minimum = votesIn + votesNeeded
        switch (hoursLeft > 0, votesNeeded > 0) {
        case (true, true):
            return "\(votesIn) of \(counted(minimum, "vote")) so far. "
                + "The grade arrives in about \(counted(hoursLeft, "hour")), once \(counted(minimum, "vote")) are in."
        case (true, false):
            return "\(counted(votesIn, "vote")) so far. The grade arrives in about \(counted(hoursLeft, "hour"))."
        case (false, true):
            return "\(votesIn) of \(counted(minimum, "vote")) so far. The grade arrives with \(votesNeeded) more."
        case (false, false):
            return "\(counted(votesIn, "vote")) so far. The grade arrives in a few minutes."
        }
    }

    /// A count with its noun, such as "1 vote" or "3 votes".
    static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    /// What the technical check read in a photo that has no grade yet. The
    /// check is advice, so it never says a photo failed or is held back.
    private func checkVerdict(for photo: SpottedPhoto) -> some View {
        let technical = model.technicalScore(for: photo)
        let passed = model.checkReport(for: photo).isPassed
        return VStack(alignment: .leading, spacing: 3) {
            if let technical {
                Text("Technical reading \(technical.scoreText)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(
                    passed
                        ? "Only you see this. Votes alone will set the grade."
                        : "Only you see this. The ideas below could lift it, and votes alone will set the grade."
                )
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
            } else if !photo.isAircraftFound {
                Text("Aircraft not found")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(aircraftNotFoundDetail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Not graded yet")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    /// Why a photo has no technical check. The simulator cannot run the
    /// request that finds the aircraft, so there it says where to try.
    private var aircraftNotFoundDetail: String {
        #if targetEnvironment(simulator)
        return "The check could not find an aircraft, so this photo was not scored. "
            + "The simulator cannot find aircraft, so try it on an iPhone."
        #else
        return "The check could not find an aircraft, so this photo was not scored."
        #endif
    }

    @ViewBuilder
    private func technicalLine(for photo: SpottedPhoto) -> some View {
        if let technical = model.technicalScore(for: photo) {
            Text("Technical reading \(technical.scoreText), seen only by you")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Feedback

    @ViewBuilder
    private func feedback(for photo: SpottedPhoto) -> some View {
        if !photo.findings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.bottom, 18)

                let fixes = Array(photo.fixes.prefix(3))
                if !fixes.isEmpty {
                    SectionHeading("To lift this shot")
                        .padding(.bottom, 4)
                    ForEach(fixes) { fix in
                        FixRow(fix: fix)
                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(height: 1)
                    }
                }

                if let passedText = passedSummary(for: photo) {
                    Label(passedText, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 14)
                }

                // The rows above are for reading. This one button is the
                // way into the full check.
                NavigationLink(value: PhotoRoute.technicalCheck(photo.id)) {
                    Text("See the technical check")
                }
                .buttonStyle(.secondary)
                .padding(.top, 18)
            }
        }
    }

    // MARK: Posting

    /// The way to post a photo for votes. The technical check never stands
    /// in the way. When it has ideas, the button says the photo can be
    /// posted anyway.
    @ViewBuilder
    private func postSection(for photo: SpottedPhoto) -> some View {
        // A build with no backend has nowhere to post, so it shows nothing.
        if let sync, sync.offersPosting, model.canBePosted(photo) {
            let hasIdeas = !photo.fixes.isEmpty
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.bottom, 6)
                SectionHeading("Post for votes")
                Text(
                    hasIdeas
                        ? "The ideas above are only advice. Other people see the photo and nothing else, and their votes alone set the grade."
                        : "Other people see the photo and nothing else, and their votes alone set the grade."
                )
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)

                // The owner chose to show the spot when the photo was
                // logged. Posting is what puts it in front of people, so
                // the screen says where it will be seen.
                if let spotName = offeredSpotName(for: photo) {
                    Text("You chose to show the spot. Once the photo is graded, it also goes on the page for \(spotName).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }

                if sync.session.isSignedIn {
                    Button {
                        isConfirmingPost = true
                    } label: {
                        if isPosting {
                            ProgressView()
                                .tint(Theme.ground)
                                .accessibilityLabel("Posting")
                        } else {
                            Text(hasIdeas ? "Post anyway" : "Post for votes")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(isPosting)

                    if let postProblem {
                        Text(Self.message(for: postProblem))
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                    }
                } else {
                    Text("Sign in on Profile to post this photo.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func post(_ photo: SpottedPhoto) {
        guard let sync, !isPosting else { return }
        isPosting = true
        postProblem = nil
        Task {
            let outcome = await sync.post(photoID: photo.id, on: model)
            isPosting = false
            postProblem = outcome == .posted ? nil : outcome
        }
    }

    /// The name of the spot whose page the photo would go on, or nil when
    /// it would go on none. A photo whose location is private has none.
    private func offeredSpotName(for photo: SpottedPhoto) -> String? {
        model.spotShowing(for: photo).flatMap { model.spot(id: $0.spotID)?.name }
    }

    /// What the user is told before a photo is posted.
    ///
    /// - Parameters:
    ///   - spotName: The spot whose page the photo goes on once graded, or
    ///     nil when it goes on none.
    ///   - showsAircraft: False for a blocked aircraft, whose type and
    ///     airline are left off the page.
    static func postWarning(spotName: String?, showsAircraft: Bool) -> String {
        var parts = ["Voters see the photo and nothing else. They do not see your name or where it was taken."]
        if let spotName {
            let shown = showsAircraft ? "its grade, aircraft type, and airline" : "its grade"
            parts.append(
                "Once it is graded, it also goes on the page for \(spotName) with \(shown). "
                    + "Your name and the registration are never shown there."
            )
        }
        parts.append("A post cannot be taken back, but deleting the photo removes it.")
        return parts.joined(separator: " ")
    }

    /// What to tell the user when a photo was not posted.
    static func message(for outcome: PostOutcome) -> String {
        switch outcome {
        case .posted:
            "The photo is posted."
        case .signInNeeded:
            "Sign in again on Profile, then post this photo."
        case .notSavedYet:
            "The photo has not reached your account yet. Check your connection and try again."
        case .imageHasLocation:
            "The photo's file has a location written inside it, so it was not posted. Add the photo again and post the new copy."
        case .photoGone:
            "This photo is no longer in your account."
        case .couldNotPost:
            "Posting did not work. Try again in a moment."
        }
    }

    // MARK: Camera

    @ViewBuilder
    private func cameraSection(for photo: SpottedPhoto) -> some View {
        if photo.camera != nil || photo.capturedAt != nil {
            VStack(alignment: .leading, spacing: 14) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.bottom, 4)
                SectionHeading("Camera")

                if let camera = photo.camera {
                    let columns = settingColumns(for: camera)
                    if !columns.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(columns) { column in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(column.value)
                                        .font(.condensed(24, relativeTo: .title3))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(column.label)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    if let gear = gearLine(for: camera) {
                        Label(gear, systemImage: "camera")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                if let capturedAt = photo.capturedAt {
                    Label(
                        "Taken \(capturedAt.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "clock"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    // MARK: Location

    /// Where the photo was taken, as its owner sees it. This screen shows
    /// only the user's own photos, so an undisclosed one is still placed.
    @ViewBuilder
    private func locationSection(for photo: SpottedPhoto) -> some View {
        if photo.hasCaptureLocation || photo.spotID != nil {
            VStack(alignment: .leading, spacing: 14) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.bottom, 4)
                SectionHeading("Location")
                Label(locationText(for: photo), systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if photo.isLocationUndisclosed {
                    Label("Only you can see where this was taken.", systemImage: "lock")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                spotPageRows(for: photo)
            }
        }
    }

    private func locationText(for photo: SpottedPhoto) -> String {
        guard let spot = model.listedSpot(for: photo) else {
            return "Taken away from the listed spots"
        }
        return "Taken near \(spot.name)"
    }

    // MARK: The spot's page

    /// Whether the photo is on its spot's page, with the way to put it
    /// there or take it off.
    ///
    /// A photo goes on the page when it is posted with its spot showing.
    /// A photo posted before spots had pages was posted with the promise
    /// that nobody sees where it was taken, so it goes on only when its
    /// owner asks here.
    @ViewBuilder
    private func spotPageRows(for photo: SpottedPhoto) -> some View {
        // Only a posted photo can be on a spot's page, and a build with no
        // backend has no pages to put it on.
        if !photo.isSample, let sync, sync.offersPosting, sync.session.isSignedIn,
           model.progress(for: photo).isPosted {
            if let showing = model.spotShowings[photo.id] {
                Label(
                    Self.shownLine(
                        spotName: model.spot(id: showing.spotID)?.name,
                        isGraded: model.finalScore(for: photo) != nil
                    ),
                    systemImage: "eye"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                Button("Take it off the spot's page") {
                    changeSpotPage(for: photo, show: false)
                }
                .buttonStyle(.secondary)
                .disabled(isChangingSpotPage)
            } else if let spotName = offeredSpotName(for: photo) {
                Text(Self.offerLine(spotName: spotName, showsAircraft: !photo.hasBlockedRegistration))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button("Show it on the spot's page") {
                    changeSpotPage(for: photo, show: true)
                }
                .buttonStyle(.secondary)
                .disabled(isChangingSpotPage)
            }
            if let spotPageProblem {
                Text(Self.message(for: spotPageProblem))
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    private func changeSpotPage(for photo: SpottedPhoto, show: Bool) {
        guard let sync, !isChangingSpotPage else { return }
        isChangingSpotPage = true
        spotPageProblem = nil
        Task {
            let outcome: SpotShowOutcome
            if show {
                outcome = await sync.showAtSpot(photoID: photo.id, on: model)
            } else {
                outcome = await sync.takeOffSpot(photoID: photo.id, on: model)
            }
            isChangingSpotPage = false
            spotPageProblem = outcome == .done ? nil : outcome
        }
    }

    /// What the owner reads about a photo that is on a spot's page.
    static func shownLine(spotName: String?, isGraded: Bool) -> String {
        let page = spotName.map { "the page for \($0)" } ?? "its spot's page"
        return isGraded
            ? "Shown on \(page)."
            : "It goes on \(page) once it is graded."
    }

    /// What the owner reads before putting a photo on a spot's page.
    static func offerLine(spotName: String, showsAircraft: Bool) -> String {
        let shown = showsAircraft ? "its grade, aircraft type, and airline" : "its grade"
        return "You can show this photo on the page for \(spotName). People who open the spot then see it with \(shown). "
            + "They never see your name or the registration."
    }

    /// What to tell the user when the spot's page could not be changed.
    static func message(for outcome: SpotShowOutcome) -> String {
        switch outcome {
        case .done:
            "The spot's page is up to date."
        case .signInNeeded:
            "Sign in again on Profile, then try again."
        case .cannotShow:
            "Only a posted photo with its spot showing can go on a spot's page."
        case .spotNotListed:
            "This photo was not taken at a listed spot."
        case .couldNotChange:
            "That did not work. Check your connection and try again."
        }
    }

    /// The settings a photo carries, each as a value over a label.
    private func settingColumns(for camera: CameraSettings) -> [SettingColumn] {
        var columns: [SettingColumn] = []
        if let focalLength = camera.focalLengthText {
            columns.append(SettingColumn(label: "Focal length", value: focalLength))
        }
        if let aperture = camera.apertureText {
            columns.append(SettingColumn(label: "Aperture", value: aperture))
        }
        if let shutter = camera.shutterText {
            columns.append(SettingColumn(label: "Shutter", value: shutter))
        }
        if let iso = camera.iso {
            columns.append(SettingColumn(label: "ISO", value: "\(iso)"))
        }
        return columns
    }

    /// The camera and lens on one line, or nil when the photo names neither.
    private func gearLine(for camera: CameraSettings) -> String? {
        let parts = [camera.cameraName, camera.lensModel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// A sentence that names the checks that passed, or nil when none did.
    private func passedSummary(for photo: SpottedPhoto) -> String? {
        let names = model.checkReport(for: photo).passed.map { $0.kind.displayName.lowercased() }
        guard let first = names.first else { return nil }
        let list = names.formatted(.list(type: .and))
        let sentence = first.prefix(1).uppercased() + String(list.dropFirst())
        switch names.count {
        case 1: return "\(sentence) passed."
        case 2: return "\(sentence) both passed."
        default: return "\(sentence) all passed."
        }
    }
}

/// One camera setting, such as "f/5.6" over "Aperture".
private struct SettingColumn: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

/// One suggested fix with the points it is worth.
private struct FixRow: View {
    let fix: SuggestedFix

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fix.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(fix.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            Text("+\(fix.points)")
                .font(.condensed(24, relativeTo: .title3))
                .foregroundStyle(Theme.gain)
                .accessibilityLabel("Worth \(fix.points) points of the technical reading")
        }
        .frame(minHeight: 62)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Graded") {
    NavigationStack {
        PhotoDetailView(photoID: "b737-n823ak")
    }
    .environment(SampleData.model())
}

#Preview("Checked, not graded") {
    let model = SampleData.model()
    model.add(SampleData.checkedPhoto(in: model))
    return NavigationStack {
        PhotoDetailView(photoID: "preview-checked")
    }
    .environment(model)
}

#Preview("Aircraft not found") {
    let model = SampleData.model()
    model.add(SampleData.unfoundPhoto)
    return NavigationStack {
        PhotoDetailView(photoID: "preview-unfound")
    }
    .environment(model)
}

#Preview("Voting") {
    NavigationStack {
        PhotoDetailView(photoID: "b2-spirit")
    }
    .environment(SampleData.model())
}

#Preview("Ready to post") {
    let model = SampleData.model()
    model.add(SampleData.loggedPhoto(in: model))
    return NavigationStack {
        PhotoDetailView(photoID: "preview-logged")
    }
    .environment(model)
    .environment(SyncCoordinator.preview(.signedIn))
}

#Preview("Post, signed out") {
    let model = SampleData.model()
    model.add(SampleData.loggedPhoto(in: model))
    return NavigationStack {
        PhotoDetailView(photoID: "preview-logged")
    }
    .environment(model)
    .environment(SyncCoordinator.preview(.signedOut))
}
