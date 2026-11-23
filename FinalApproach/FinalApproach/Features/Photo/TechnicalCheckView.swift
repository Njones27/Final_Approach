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
        .toolbarVisibility(.hidden, for: .tabBar)
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
                        ForEach(needsWork) { finding in
                            CheckRow(finding: finding, tint: Theme.fill(for: .bronze))
                        }
                    }
                }

                if !passed.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading("Passed")
                        ForEach(passed) { finding in
                            CheckRow(finding: finding, tint: Theme.ink)
                        }
                    }
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
            ScoreMeter(score: finding.result.score, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        TechnicalCheckView(photoID: "a350-n502dn")
    }
    .environment(SampleData.model())
}
