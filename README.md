# Final Approach

Final Approach is a plane spotting photography app for iOS. Spotters
photograph real aircraft to build a collection of types, airlines, and
individual airframes, and better photos are worth more. Each graded shot gets
an on-device technical check and community votes, with specific feedback on
what to fix.

The project is at the UI stage. Every screen is built in SwiftUI and runs on
sample data. Importing real photos, the technical check, and the backend come
next, one milestone at a time.

## What's inside

| Path | Contents |
| --- | --- |
| `FinalApproach/` | The Xcode project, the SwiftUI app, its unit tests, build config, and the Xcode Cloud scripts |
| `Packages/FinalApproachCore/` | Pure Swift domain logic, tested on Linux and macOS |
| `.github/workflows/` | GitHub Actions checks |
| `docs/design-context.md` | The product design context |
| `docs/build-plan.md` | Decisions and milestones |
| `docs/ci-cd.md` | CI/CD, environments, and the Xcode Cloud setup steps |
| `docs/local-development.md` | Running the app and using Claude Code with the simulator |

## Getting started

1. Open `FinalApproach/FinalApproach.xcodeproj` in Xcode 26 or later.
2. Pick an iPhone simulator and press Run.

Run the core package tests with:

```sh
swift test --package-path Packages/FinalApproachCore
```

## CI/CD

Xcode Cloud builds the app and ships it to TestFlight. GitHub Actions tests the
core package and the Xcode Cloud scripts on every pull request. See
`docs/ci-cd.md` for the full setup.
