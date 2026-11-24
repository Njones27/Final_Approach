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
| Backend type check, tests, and template build (`backend/`) | GitHub Actions, Linux | Every pull request and push to `main` |
| Backend deploy to beta | GitHub Actions, Linux | Push to `main` that changes `backend/`, or by hand from the Actions tab |
| Backend deploy to prod | GitHub Actions, Linux | After the beta deploy of the same run passes, and only once the owner approves it |

## Environments

| Stage | Backend | App build | Audience |
| --- | --- | --- | --- |
| dev | None yet, sample data | Debug build from Xcode | Local simulator and device |
| beta | AWS beta account | Xcode Cloud Beta workflow | Internal TestFlight testers |
| prod | AWS prod account, created before launch | Xcode Cloud Release workflow | External TestFlight and the App Store |

The app has one bundle ID, `com.finalapproach.app`, and one App Store Connect
record. The environment is a build setting.

1. `FinalApproach/Config/App.xcconfig` defines `APP_ENVIRONMENT`,
   `APP_DISPLAY_NAME`, `API_HOST`, `AUTH_HOST`, and `AUTH_CLIENT_ID`. Its
   defaults are the dev values, which name no backend.
2. `FinalApproach/Config/Stages/<stage>.xcconfig` holds the backend for one
   stage, which is the API host, the host the app signs in at, and the id
   the user pool gave the app. `beta.xcconfig` exists. `prod.xcconfig` is
   added when prod is deployed.
3. Each Xcode Cloud workflow sets the `APP_ENVIRONMENT` environment variable
   to `beta` or `prod`.
4. `FinalApproach/ci_scripts/ci_post_clone.sh` runs after Xcode Cloud clones
   the repo and writes `Config/Environment.generated.xcconfig`, which
   `App.xcconfig` includes when it exists. The generated file includes the
   stage's file first and then sets the environment and the display name.
5. `Info.plist` carries the values into the app, and `AppEnvironment.swift`
   reads them.

The backend's values ship inside the app, so they are not secrets, and they
live in the repo so that a build never depends on a value typed into Xcode
Cloud. An `API_HOST` environment variable in a workflow still replaces the
stage's host, which is of use only for pointing one build somewhere else.

Each host is a bare host name with no scheme, because a double slash starts a
comment in an xcconfig file. GitHub Actions checks that every stage file
holds bare values only.

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
| Start condition | Branch Changes, branch `main` |
| Start condition, files and folders | Start a build only when files change in `FinalApproach/` or `Packages/` |
| Start condition, auto-cancel builds | On |
| Action 1 | Test, scheme `FinalApproach`, platform iOS Simulator, one recommended iPhone |
| Action 2 | Archive, scheme `FinalApproach`, platform iOS, deployment preparation TestFlight (Internal Testing Only) |
| Post-action | TestFlight Internal Testing, with the internal tester group |

### Release workflow

Create this one shortly before launch, after the prod AWS account exists and
`FinalApproach/Config/Stages/prod.xcconfig` holds the prod backend.

| Setting | Value |
| --- | --- |
| Name | Release |
| Environment variable | `APP_ENVIRONMENT` = `prod` |
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
It calls two reusable workflows. `.github/workflows/core-checks.yml` has two
jobs, and `.github/workflows/backend-checks.yml` has one.
`.github/workflows/backend-deploy.yml` is separate and deploys the backend to
beta. It is described below.

- **Core package tests** builds and tests `Packages/FinalApproachCore` in the
  official `swift` container image.
- **Xcode Cloud script checks** lints `ci_scripts` with shellcheck and runs the
  post-clone script against a temporary directory.
- **Backend tests and templates** type checks `backend/`, runs its tests, and
  builds the templates for both stages in the official `node` container image.
  It needs no AWS account.

Conventions, carried over from WalkWorthy:

- Actions are pinned by full commit SHA with the release in a comment.
- Each workflow declares the least `permissions` it needs.
- The pull request workflow has no path filter, so a required check always
  reports.
- Secrets live only in App Store Connect and GitHub, never in the repo.

### Deploying the backend

`.github/workflows/backend-deploy.yml` runs when a push to `main` changes
`backend/`, and the owner can start it by hand from the Actions tab. It has
one job for each stage, and both jobs run the same steps, which are in
`.github/actions/deploy-backend/action.yml`.

1. **Checks.** The backend type check, tests, and template build.
2. **Deploy to beta.** Shows what will change, deploys the three backend
   stacks to the beta account, and checks that the API turns away a request
   with no sign in.
3. **Deploy to prod.** Waits for the owner to approve the run, then does the
   same in the prod account. It runs only after beta passed.

The prod job names the GitHub environment `prod`. That environment has the
owner as a required reviewer, so GitHub holds the job and sends the owner a
request to review it. Approving it deploys prod, and rejecting it or leaving
it alone deploys nothing. Before it deploys, the job checks that `main` does
not hold a newer backend than the run does, so approving an old run cannot
take prod back. A run started by hand stops after beta unless prod is chosen.

Each stage deploys one at a time. Each has its own queue, so a prod deploy
that waits for approval never holds up beta.

No AWS keys are stored in GitHub. A job asks GitHub for a short lived token
that says where it runs, and trades it for one hour of access to the stage's
account. The role it takes on is the stage's `Deploy` stack.

- The beta role accepts a token only from the `main` branch of this
  repository, named by its name and its id.
- The prod role accepts a token only from a job in the `prod` environment of
  this repository. GitHub starts such a job only from `main` and only after
  the approval, because the environment's settings say so.

A pull request or a fork cannot deploy either stage.

The workflow reads the roles from the repository variables
`BETA_DEPLOY_ROLE_ARN` and `PROD_DEPLOY_ROLE_ARN`, so no account id is
written in the repo. The prod job is left out of every run until
`PROD_DEPLOY_ROLE_ARN` is set. The one time setup is in `docs/backend.md`.

Anyone who can push to `main` can change what runs in the beta account, so
keep `main` protected. Prod also needs the approval. The settings of the
`prod` environment are part of what keeps prod safe, so do not remove its
reviewer or its limit to `main`.

## AWS accounts

There is one AWS account for each stage. On the owner's Mac the beta account
is the AWS CLI profile `fa_beta`. Every workload goes to beta first. The prod account stays
empty until the owner sets up its deploy role and approves a first deploy.

The `beta` stage of the backend is deployed in `us-east-1`. The CDK app takes
the stage from `-c stage=<name>` and the account from the profile in use.
GitHub Actions deploys beta when a backend change reaches `main`, and prod
after the owner approves the same run. The steps are in `docs/backend.md`.
