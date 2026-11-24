import FinalApproachCore
import SwiftUI

/// Every technical check for one photo. The checks that need work come
/// first, weakest first, and each one says what to fix.
struct TechnicalCheckView: View {
    let photoID: String

    @Environment(CollectionModel.self) private var model

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
        .navigationTitle("Technical check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for photo: SpottedPhoto) -> some View {
        let report = model.checkReport(for: photo)
        let needsWork = findings(for: report.needsWork, in: photo)
        let passed = findings(for: report.passed, in: photo)

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summary(for: photo, report: report)

                if !needsWork.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading("Fix these first")
                        ForEach(Array(needsWork.enumerated()), id: \.element.id) { index, finding in
                            CheckRow(finding: finding, tint: Theme.fill(for: .bronze), order: index)
                        }
                    }
                }

                if !passed.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading("Passed")
                        ForEach(Array(passed.enumerated()), id: \.element.id) { index, finding in
                            CheckRow(finding: finding, tint: Theme.ink, order: needsWork.count + index)
                        }
                    }
                }

                if let notChecked = notCheckedSummary(for: photo) {
                    Text(notChecked)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    private func summary(for photo: SpottedPhoto, report: TechnicalCheckReport) -> some View {
        HStack(alignment: .center, spacing: 16) {
            PhotoFill(image: model.image(for: photo), description: photo.imageDescription)
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if let overall = report.overallScore() {
                    Text(overall.scoreText)
                        .font(.condensed(56, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Technical check \(overall.scoreText) out of 100")
                }
                Text("This is \(technicalShare) percent of the grade. Votes decide the rest.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// The technical check's share of the final grade, as a whole percent.
    private var technicalShare: Int {
        Int((model.gradeWeights.ai * 100).rounded())
    }

    /// A sentence that names the checks that did not run on this photo, or
    /// nil when every check ran. A check is left out when there was nothing
    /// to measure, such as a horizon in a photo of open sky.
    private func notCheckedSummary(for photo: SpottedPhoto) -> String? {
        let names = CheckKind.allCases
            .filter { kind in !photo.findings.contains { $0.result.kind == kind } }
            .map { $0.displayName.lowercased() }
        guard let first = names.first else { return nil }
        let list = names.formatted(.list(type: .and))
        let sentence = first.prefix(1).uppercased() + String(list.dropFirst())
        return names.count == 1
            ? "\(sentence) was not checked on this photo."
            : "\(sentence) were not checked on this photo."
    }

    /// The written findings for a list of results, in the same order.
    private func findings(for results: [CheckResult], in photo: SpottedPhoto) -> [CheckFinding] {
        results.compactMap { result in
            photo.findings.first { $0.result.kind == result.kind }
        }
    }
}

/// One check with its score, a meter, and a sentence about what it saw.
private struct CheckRow: View {
    let finding: CheckFinding
    let tint: Color
    /// The row's place on the screen, so the meters fill from the top down.
    let order: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.result.kind.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(finding.detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Text(finding.result.score.scoreText)
                    .font(.condensed(24, relativeTo: .title3))
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("\(finding.result.score.scoreText) out of 100")
            }
            ScoreMeter(score: finding.result.score, tint: tint, order: order)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        TechnicalCheckView(photoID: "b737-n823ak")
    }
    .environment(SampleData.model())
}

#Preview("Imported photo") {
    let model = SampleData.model()
    model.add(SampleData.checkedPhoto(in: model))
    return NavigationStack {
        TechnicalCheckView(photoID: "preview-checked")
    }
    .environment(model)
}
