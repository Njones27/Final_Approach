import FinalApproachCore
import SwiftUI
import UIKit

/// Shows one photo at a time and takes a vote in stars.
///
/// Voting is blind. The screen shows the photo and nothing else, so the
/// photographer, the place, and the score cannot sway the vote. A build
/// with a backend votes on photos other people posted. A build with none
/// keeps the sample set.
struct VoteView: View {
    @Environment(CollectionModel.self) private var model
    /// It is nil in a preview that has no backend, which shows the sample
    /// set.
    @Environment(VotingModel.self) private var voting: VotingModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The model that votes against the backend, or nil when this build
    /// keeps the sample set.
    private var live: VotingModel? {
        guard let voting, voting.isLive else { return nil }
        return voting
    }

    var body: some View {
        NavigationStack {
            Group {
                if let live {
                    liveContent(live)
                } else {
                    sampleContent
                }
            }
            .arrivesWithTab()
            .background(Theme.ground)
            .navigationTitle("Vote")
            .toolbar {
                if canSkip {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip", action: skip)
                            .disabled(live?.isBusy == true)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: votesCast)
        }
        .task(id: voting?.session.state) {
            await voting?.refresh()
        }
    }

    private var canSkip: Bool {
        if let live { return live.session.isSignedIn && live.ballot != nil }
        return model.currentVoteCandidate != nil
    }

    /// The count that changes each time a vote is counted.
    private var votesCast: Int {
        live?.votesCast ?? model.profile.votesCast
    }

    private func skip() {
        if let live {
            Task { await live.skip() }
        } else {
            withAnimation(Motion.swap) {
                model.skipVote()
            }
        }
    }

    // MARK: Photos other people posted

    @ViewBuilder
    private func liveContent(_ voting: VotingModel) -> some View {
        // A photo loaded for one user is never shown once they sign out.
        if voting.session.isSignedIn, let ballot = voting.ballot {
            ballotLayout(
                id: ballot.id,
                image: Image(uiImage: ballot.image),
                imageSize: ballot.image.size,
                caption: nil,
                scale: voting.scale,
                isBusy: voting.isBusy,
                problem: voting.lastVoteFailed
                    ? "Your vote was not counted. Check your connection and try again."
                    : nil
            ) { stars in
                Task { await voting.cast(stars) }
            }
            .animation(Motion.swap, value: ballot.id)
        } else {
            switch voting.phase {
            case .idle, .loading, .voting:
                ProgressView("Finding photos")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView {
                    Label("Nothing to vote on right now", systemImage: "checkmark.circle")
                } description: {
                    Text("You have seen every photo that is open for votes. New ones show up here as people post them.")
                } actions: {
                    Button("Check again") {
                        Task { await voting.refresh() }
                    }
                }
            case .signInNeeded:
                ContentUnavailableView(
                    "Sign in to vote",
                    systemImage: "person.crop.circle",
                    description: Text("Sign in on Profile to vote on photos other people posted.")
                )
            case .couldNotLoad:
                ContentUnavailableView {
                    Label("The photos could not be loaded", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") {
                        Task { await voting.refresh() }
                    }
                }
            }
        }
    }

    // MARK: The sample set

    @ViewBuilder
    private var sampleContent: some View {
        if let candidate = model.currentVoteCandidate {
            ballotLayout(
                id: candidate.id,
                image: Image(candidate.imageName),
                imageSize: UIImage(named: candidate.imageName)?.size ?? .zero,
                caption: "Photo \(model.votePosition) of \(model.voteSetSize) in today's set",
                scale: model.votingRules.scale,
                isBusy: false,
                problem: nil
            ) { stars in
                withAnimation(Motion.swap) {
                    model.castVote(stars)
                }
            }
        } else {
            ContentUnavailableView(
                "You are done for today",
                systemImage: "checkmark.circle",
                description: Text("You have seen every photo in today's set.")
            )
        }
    }

    // MARK: One photo and its stars

    private func ballotLayout(
        id: String,
        image: Image,
        imageSize: CGSize,
        caption: String?,
        scale: ClosedRange<Int>,
        isBusy: Bool,
        problem: String?,
        cast: @escaping (Int) -> Void
    ) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let caption {
                        Text(caption)
                            .font(.subheadline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    // The whole photo shows, because a voter judges the
                    // framing too. A tall photo is held to part of the
                    // screen so the stars stay in view.
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.photoHeight(for: imageSize, in: proxy.size))
                        .background(Theme.surface)
                        .accessibilityLabel("The photo to vote on")
                        .id(id)
                        .transition(photoTransition)

                    StarBallot(scale: scale, isBusy: isBusy, problem: problem, cast: cast)
                        // A new photo starts with no stars picked.
                        .id(id)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 32)
                }
            }
        }
    }

    /// The most of the screen's height a photo takes.
    private static let photoShare: CGFloat = 0.55

    /// How tall the photo is drawn. A wide photo takes the full width. A
    /// tall one is held to a share of the screen, and narrows to fit.
    static func photoHeight(for image: CGSize, in screen: CGSize) -> CGFloat {
        let limit = screen.height * photoShare
        guard image.width > 0, image.height > 0 else { return limit }
        return min(screen.width * image.height / image.width, limit)
    }

    /// What VoiceOver reads for one star.
    static func spokenLabel(for value: Int, in scale: ClosedRange<Int>) -> String {
        let stars = value == 1 ? "1 star" : "\(value) stars"
        if value == scale.lowerBound { return "\(stars), poor" }
        if value == scale.upperBound { return "\(stars), excellent" }
        return stars
    }

    /// The voted photo leaves to the leading side as the next one arrives
    /// from the trailing side. With Reduce Motion on they fade.
    private var photoTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

/// The stars under a photo and the button that casts the vote.
///
/// A vote cannot be changed once it is cast. So picking a star only marks
/// it, and the vote is cast with the button.
private struct StarBallot: View {
    let scale: ClosedRange<Int>
    let isBusy: Bool
    /// Why the last vote did not count, or nil.
    let problem: String?
    let cast: (Int) -> Void

    @State private var picked: Int?
    /// Counts taps on a star, so tapping the same star again pops it again.
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How good is this photo?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text("You see the photo and nothing else. The photographer, the place, and the score stay hidden.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            stars

            Button {
                if let picked { cast(picked) }
            } label: {
                if isBusy {
                    ProgressView()
                        .tint(Theme.ground)
                        .accessibilityLabel("Working")
                } else {
                    Text("Cast vote")
                }
            }
            .buttonStyle(.primary)
            .disabled(picked == nil || isBusy)
            .opacity(picked == nil ? 0.4 : 1)

            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
            }

            Text("Pick your stars, then cast the vote. Judge the photo as a whole. A vote cannot be changed once it is cast.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .sensoryFeedback(.selection, trigger: picked)
    }

    /// One star for each value on the voting scale.
    private var stars: some View {
        let values = Array(scale)
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    let isFilled = value <= (picked ?? 0)
                    Button {
                        withAnimation(Motion.press) {
                            picked = value
                        }
                        taps += 1
                    } label: {
                        Image(systemName: isFilled ? "star.fill" : "star")
                            // The picked stars spring up one after another,
                            // from the first to the one that was tapped.
                            // With Reduce Motion on they only change color.
                            .phaseAnimator([false, true], trigger: taps) { star, isRaised in
                                star.scaleEffect(isRaised && isFilled && !reduceMotion ? Motion.popScale : 1)
                            } animation: { isRaised in
                                isRaised
                                    ? Motion.pop.delay(Double(value - scale.lowerBound) * Motion.stagger)
                                    : Motion.settle
                            }
                    }
                    .buttonStyle(StarButtonStyle(isFilled: isFilled))
                    .disabled(isBusy)
                    .accessibilityLabel(VoteView.spokenLabel(for: value, in: scale))
                    .accessibilityAddTraits(picked == value ? .isSelected : [])
                    if value != values.last {
                        Spacer(minLength: 4)
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

}

/// A star that dims and shrinks while pressed.
private struct StarButtonStyle: ButtonStyle {
    let isFilled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title)
            .foregroundStyle(isFilled ? Theme.star : Theme.chevron)
            .frame(minWidth: 44, minHeight: 56)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

#Preview("Sample set") {
    VoteView()
        .environment(SampleData.model())
}

#Preview("Other people's photos") {
    let sync = SyncCoordinator.preview(.signedIn)
    VoteView()
        .environment(SampleData.model())
        .environment(VotingModel.preview(session: sync.session))
}

#Preview("Signed out") {
    let sync = SyncCoordinator.preview(.signedOut)
    VoteView()
        .environment(SampleData.model())
        .environment(VotingModel.preview(session: sync.session))
}

#Preview("Nothing to vote on") {
    let sync = SyncCoordinator.preview(.signedIn)
    VoteView()
        .environment(SampleData.model())
        .environment(VotingModel.preview(session: sync.session, posts: []))
}
