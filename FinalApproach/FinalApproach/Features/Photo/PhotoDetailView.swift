import FinalApproachCore
import SwiftUI

/// One photo with its grade, where the grade sits on the tier scale, and the
/// fixes that would lift it.
struct PhotoDetailView: View {
    let photoID: String

    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

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
        .toolbarVisibility(.hidden, for: .tabBar)
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
                    cameraSection(for: photo)
                        .revealed(order: 3)
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
                    preview: SharePreview(photo.aircraftType, image: model.image(for: photo))
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More actions", systemImage: "ellipsis") {
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
            Text("The photo and its grade are removed from your collection.")
        }
    }

    // MARK: Header

    private func header(for photo: SpottedPhoto) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(photo.aircraftType)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.ink)
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
        switch photo.status {
        case let .graded(voteAverage, voteCount):
            if let score = model.finalScore(for: photo) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 18) {
                        Text(score.scoreText)
                            .font(.condensed(78, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.ink)
                            .accessibilityLabel("Grade \(score.scoreText)")
                        VStack(alignment: .leading, spacing: 3) {
                            TierLabel(tier: model.tier(for: photo))
                            technicalLine(for: photo)
                            Text("Votes \(voteAverage.formatted(.number.precision(.fractionLength(1)))) from \(voteCount) people")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    TierScaleView(score: score, thresholds: model.thresholds)
                }
            }
        case let .voting(votesIn, hoursLeft):
            VStack(alignment: .leading, spacing: 3) {
                Text("Voting is open")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("\(votesIn) of \(model.votingRules.minimumVotes) votes so far. The grade arrives in about \(hoursLeft) hours.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                technicalLine(for: photo)
            }
        case .logged:
            checkVerdict(for: photo)
        }
    }

    /// What the technical check decided for a photo that has no grade yet.
    /// The check is the gate before voting, so the verdict leads.
    private func checkVerdict(for photo: SpottedPhoto) -> some View {
        let technical = model.technicalScore(for: photo)
        let passed = model.checkReport(for: photo).isPassed
        return VStack(alignment: .leading, spacing: 3) {
            if let technical {
                Text(passed ? "Technical check passed" : "Technical check needs work")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(
                    passed
                        ? "It scored \(technical.scoreText). Votes decide the rest of the grade."
                        : "It scored \(technical.scoreText). The fixes below would lift it."
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
            Text("Technical check \(technical.scoreText)")
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
                        NavigationLink(value: PhotoRoute.technicalCheck(photo.id)) {
                            FixRow(fix: fix)
                        }
                        .buttonStyle(.plain)
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

                if fixes.isEmpty {
                    NavigationLink(value: PhotoRoute.technicalCheck(photo.id)) {
                        Text("See the technical check")
                    }
                    .buttonStyle(.secondary)
                    .padding(.top, 18)
                }
            }
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
                .accessibilityLabel("Worth \(fix.points) points")
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.chevron)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
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
