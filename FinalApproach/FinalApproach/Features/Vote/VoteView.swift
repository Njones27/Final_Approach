import FinalApproachCore
import SwiftUI

/// Shows one photo at a time and takes a vote on the voting scale. The
/// photographer and the score stay hidden so they cannot sway the vote.
struct VoteView: View {
    @Environment(CollectionModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let candidate = model.currentVoteCandidate {
                    ballot(for: candidate)
                } else {
                    ContentUnavailableView(
                        "You are done for today",
                        systemImage: "checkmark.circle",
                        description: Text("You have seen every photo in today's set.")
                    )
                }
            }
            .background(Theme.ground)
            .navigationTitle("Vote")
            .toolbar {
                if model.currentVoteCandidate != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") {
                            withAnimation(.snappy) {
                                model.skipVote()
                            }
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: model.profile.votesCast)
        }
    }

    private func ballot(for candidate: VoteCandidate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Photo \(model.votePosition) of \(model.voteSetSize) in today's set")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                PhotoFill(imageName: candidate.imageName, description: candidate.aircraftType)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .id(candidate.id)
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.aircraftType)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        Text("The photographer and the score stay hidden until you vote.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    scale

                    Text("Tap a score to vote and move to the next photo. Judge the sharpness, the light, and the framing.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
    }

    /// One round button for each value on the voting scale.
    private var scale: some View {
        let votes = Array(model.votingRules.scale)
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(votes, id: \.self) { vote in
                    Button {
                        withAnimation(.snappy) {
                            model.castVote(vote)
                        }
                    } label: {
                        Text("\(vote)")
                    }
                    .buttonStyle(VoteButtonStyle())
                    .accessibilityLabel(spokenLabel(for: vote, in: votes))
                    if vote != votes.last {
                        Spacer(minLength: 8)
                    }
                }
            }
            HStack {
                Text("Poor")
                Spacer()
                Text("Excellent")
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
        }
    }

    private func spokenLabel(for vote: Int, in votes: [Int]) -> String {
        if vote == votes.first { return "\(vote), poor" }
        if vote == votes.last { return "\(vote), excellent" }
        return "\(vote)"
    }
}

/// A round vote button that dims and shrinks while pressed.
private struct VoteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.condensed(26, relativeTo: .title2))
            .foregroundStyle(Theme.ink)
            .frame(width: 56, height: 56)
            .background(Theme.controlFill, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    VoteView()
        .environment(SampleData.model())
}
