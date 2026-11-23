# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project overview

Final Approach is an iOS app for plane spotting photography. Its main idea is
that the app grades the photo itself, with an on-device technical check plus
community votes, and gives feedback the photographer can act on. Read
`docs/design-context.md` for the product requirements and `docs/build-plan.md`
for decisions and milestones before starting a feature.

## Layout

- `FinalApproach/FinalApproach.xcodeproj` is the Xcode project. It uses file
  system synchronized groups, so a file added under `FinalApproach/FinalApproach/`
  or `FinalApproach/FinalApproachTests/` joins its target without a project
  file edit.
- `FinalApproach/FinalApproach/` is the SwiftUI app. `App/` holds the entry
  point, environment, and settings. `Design/` holds the theme and shared
  views. `Models/` holds app state and sample data. `Services/` holds code
  that reads from the system or an external service, such as the photo
  metadata reader and the on-device photo store. `Features/` holds one folder
  per screen.
- `FinalApproach/FinalApproachTests/` holds app unit tests (Swift Testing).
- `FinalApproach/Config/App.xcconfig` holds environment build settings.
- `FinalApproach/ci_scripts/` holds Xcode Cloud scripts.
- `Packages/FinalApproachCore/` is a local Swift package with pure domain
  logic such as tiers, grade blending, and voting rules.

## Build and test

```sh
# Core package, runs on macOS and Linux
swift test --package-path Packages/FinalApproachCore

# App build and tests, macOS only
xcodebuild build -project FinalApproach/FinalApproach.xcodeproj -scheme FinalApproach \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project FinalApproach/FinalApproach.xcodeproj -scheme FinalApproach \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use `xcrun simctl list devices available` to find a simulator name that exists
on this Mac.

## Architecture rules

- `FinalApproachCore` must not import Apple-only frameworks such as SwiftUI,
  CoreLocation, Vision, or ImageIO. Its tests run on Linux in GitHub Actions.
  Code that needs those frameworks belongs in the app target.
- Put logic that can be pure in the core package and test it there. Scores,
  thresholds, weights, and voting rules are data passed in, not constants
  buried in functions, because the design requires them to be tunable without
  a release.
- The app target uses default MainActor isolation
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Types in the core package are
  `Sendable` values.
- External services such as flight data sit behind a protocol with a sample
  data implementation, so screens can be built and previewed without a
  backend.
- Read the backend environment through `AppEnvironment`. Do not hardcode hosts.

## Swift conventions

- Use Swift concurrency (`async`/`await`, actors) and the Observation
  framework (`@Observable`) for new state.
- Use Swift Testing (`import Testing`) for new tests.
- Date formatters are cached static constants. ISO date formatters set
  `locale = Locale(identifier: "en_US_POSIX")`.
- Wrap debug-only logging in `#if DEBUG`.
- Every new screen gets a `#Preview` that uses sample data.

## Interface conventions

- Take every color from `Theme` in `Design/Theme.swift`. Do not write a color
  literal in a screen, and do not branch on the color scheme.
- Use the system font for interface text. Use `Font.condensed` only for grade
  numbers, registrations, and counts.
- Use the system tab bar, toolbars, and sheets so they keep Liquid Glass. The
  tab bar holds sections only. An action is a button.
- A control that has no destination yet is left out until its milestone.
- Take every animation's timing from `Motion` in `Design/Motion.swift`. Do not
  write a duration in a screen. Anything that travels gets a still or fading
  version for Reduce Motion.
- A file that uses a type from `FinalApproachCore` imports it, because member
  import visibility is on.

## Product constraints that affect code

- Never use Forza names, logos, or assets.
- Hide the identity of blocked registrations, such as aircraft on the FAA
  LADD list.
- A post marked undisclosed shows no location to any other user.
- Deleting a photo or an account removes the stored images. A new place that
  keeps a copy of a photo must be cleared by both deletes.
- Do not scrape other photo sites, and follow the flight data provider's
  license terms.

## CI/CD

GitHub Actions runs the core package tests and the `ci_scripts` checks on every
pull request. Xcode Cloud builds the app on merges to `main`. Details and the
environment mechanism are in `docs/ci-cd.md`. Pin every GitHub Action by full
commit SHA with the release in a trailing comment.
