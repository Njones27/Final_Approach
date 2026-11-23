import SwiftUI

/// Confirms the aircraft a new photo was matched to, shows why it matched,
/// and logs it. The user only confirms, and can keep the location private.
struct AddPhotoView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LocationPrivacySetting.storageKey) private var privacySetting = LocationPrivacySetting.askEachTime
    @State private var phase = Phase.matching
    @State private var showsSpot = true

    private enum Phase {
        case matching
        case matched(FlightMatch)
        case noMatch
        case failed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .matching:
                    ProgressView("Matching your photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .matched(match):
                    matchedContent(for: match)
                case .noMatch:
                    ContentUnavailableView(
                        "No match found",
                        systemImage: "airplane",
                        description: Text("We could not match this photo to a flight.")
                    )
                case .failed:
                    ContentUnavailableView {
                        Label("Flight data is unavailable", systemImage: "wifi.slash")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try again") {
                            Task { await loadMatch() }
                        }
                    }
                }
            }
            .background(Theme.ground)
            .navigationTitle("New photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            showsSpot = privacySetting.showsSpotByDefault
            await loadMatch()
        }
    }

    private func loadMatch() async {
        phase = .matching
        do {
            if let match = try await model.flightData.matchNewPhoto() {
                phase = .matched(match)
            } else {
                phase = .noMatch
            }
        } catch {
            phase = .failed
        }
    }

    private func matchedContent(for match: FlightMatch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PhotoFill(imageName: match.photo.imageName, description: match.photo.imageDescription)
                    .aspectRatio(3 / 2, contentMode: .fit)

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.photo.aircraftType)
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if let registration = match.photo.visibleRegistration {
                                Text(registration)
                                    .font(.condensed(18, weight: .medium, relativeTo: .subheadline))
                                    .tracking(1)
                                    .foregroundStyle(Theme.ink)
                            }
                            Text("\(match.photo.airline), \(match.photo.activity)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading("How we matched it")
                        ForEach(match.evidence) { evidence in
                            EvidenceRow(evidence: evidence)
                        }
                    }

                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)

                    Toggle(isOn: $showsSpot) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show the spot to other people")
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                            Text("Turn this off to keep the location private.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .tint(Theme.switchOn)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Log this photo") {
                log(match)
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.ground)
        }
    }

    private func log(_ match: FlightMatch) {
        var photo = match.photo
        photo.isLocationUndisclosed = !showsSpot
        model.add(photo)
        dismiss()
    }
}

/// One reason the photo was matched, with where the reason came from.
private struct EvidenceRow: View {
    let evidence: MatchEvidence

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: evidence.systemImage)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(evidence.title)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Text(evidence.source)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AddPhotoView()
        .environment(SampleData.model())
}
