# CI/CD and environments

Xcode Cloud builds, signs, and ships the iOS app. GitHub Actions runs every
check that works on Linux. This is the same split the WalkWorthy repo uses.

| Job | Runs on | When |
| --- | --- | --- |
| Core package tests (`Packages/FinalApproachCore`) | GitHub Actions, Linux | Every pull request and push to `main` |
| `ci_scripts` lint and behavior checks | GitHub Actions, Linux | Every pull request and push to `main` |
| App build and unit tests in the simulator | Xcode Cloud | Merge to `main` |
| Archive and internal TestFlight | Xcode Cloud, Beta workflow | Merge to `main` |
| Archive, external TestFlight, App Store | Xcode Cloud, Release workflow | Version tag such as `v1.0.0` |
| Backend checks and deploys | GitHub Actions | Added with the backend |

## Environments

| Stage | Backend | App build | Audience |
| --- | --- | --- | --- |
| dev | None yet, sample data | Debug build from Xcode | Local simulator and device |
| beta | AWS beta account | Xcode Cloud Beta workflow | Internal TestFlight testers |
| prod | AWS prod account, created before launch | Xcode Cloud Release workflow | External TestFlight and the App Store |

The app has one bundle ID, `com.finalapproach.app`, and one App Store Connect
record. The environment is a build setting.

1. `FinalApproach/Config/App.xcconfig` defines `APP_ENVIRONMENT`,
   `APP_DISPLAY_NAME`, and `API_HOST`. Its defaults are the dev values.
2. Each Xcode Cloud workflow sets the `APP_ENVIRONMENT` environment variable
   to `beta` or `prod`.
3. `FinalApproach/ci_scripts/ci_post_clone.sh` runs after Xcode Cloud clones
   the repo and writes `Config/Environment.generated.xcconfig`, which
   `App.xcconfig` includes when it exists.
4. `Info.plist` carries the values into the app, and `AppEnvironment.swift`
   reads them.

`API_HOST` is a bare host name with no scheme, because a double slash starts a
comment in an xcconfig file.

## Xcode Cloud setup

Xcode Cloud workflows live in App Store Connect and cannot be created from the
repo. These steps are done once in Xcode.

### Before the first workflow

1. Register the bundle ID `com.finalapproach.app` under Certificates,
   Identifiers & Profiles.
2. Create the app record in App Store Connect with that bundle ID.
3. Open `FinalApproach/FinalApproach.xcodeproj` in Xcode and confirm the app
   builds and runs in a simulator.
4. Choose Product > Xcode Cloud > Create Workflow, pick the Final Approach app,
   and grant Xcode Cloud access to the `Njones27/Final_Approach` repository
   when asked.

### Beta workflow

| Setting | Value |
| --- | --- |
| Name | Beta |
| Environment, Xcode version | Latest Release |
| Environment, macOS version | Latest Release |
| Environment variable | `APP_ENVIRONMENT` = `beta` |
| Environment variable, once the backend exists | `API_HOST` = the beta API host name |
| Start condition | Branch Changes, branch `main` |
| Start condition, files and folders | Start a build only when files change in `FinalApproach/` or `Packages/` |
| Start condition, auto-cancel builds | On |
| Action 1 | Test, scheme `FinalApproach`, platform iOS Simulator, one recommended iPhone |
| Action 2 | Archive, scheme `FinalApproach`, platform iOS, deployment preparation TestFlight (Internal Testing Only) |
| Post-action | TestFlight Internal Testing, with the internal tester group |

### Release workflow

Create this one shortly before launch, after the prod AWS account exists.

| Setting | Value |
| --- | --- |
| Name | Release |
| Environment variable | `APP_ENVIRONMENT` = `prod` |
| Environment variable | `API_HOST` = the prod API host name |
| Start condition | Tag Changes, tags beginning with `v` |
| Action 1 | Test, same as Beta |
| Action 2 | Archive, deployment preparation TestFlight and App Store |
| Post-action | TestFlight External Testing |

Xcode Cloud sets the build number for each archive, so `CURRENT_PROJECT_VERSION`
does not need to change by hand. Bump `MARKETING_VERSION` for each release.

### Staying inside the free compute hours

The Apple Developer Program includes 25 Xcode Cloud compute hours a month.

- Pull requests never start an Xcode Cloud build. The Linux checks cover them.
- The files and folders condition keeps docs and backend changes from starting
  an app build.
- Auto-cancel stops a build when a newer commit lands.
- Tests run on one simulator, not a device matrix.

## GitHub Actions

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`.
It calls the reusable `.github/workflows/core-checks.yml`, which has two jobs.

- **Core package tests** builds and tests `Packages/FinalApproachCore` in the
  official `swift` container image.
- **Xcode Cloud script checks** lints `ci_scripts` with shellcheck and runs the
  post-clone script against a temporary directory.

Conventions, carried over from WalkWorthy:

- Actions are pinned by full commit SHA with the release in a comment.
- Each workflow declares the least `permissions` it needs.
- The pull request workflow has no path filter, so a required check always
  reports.
- Secrets live only in App Store Connect and GitHub, never in the repo.

## AWS accounts

The backend does not exist yet. The plan for it:

1. Create the AWS account and turn on AWS Organizations. That account handles
   billing and sign-in only.
2. Create a member account named `beta` and deploy every workload there.
3. Create a `prod` member account shortly before public launch.

The CDK app will take the stage and account from configuration, and GitHub
Actions will deploy by assuming an IAM role through OIDC, so no AWS keys are
stored in GitHub.
