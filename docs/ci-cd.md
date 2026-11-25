# CI/CD and environments

Xcode Cloud builds, signs, and ships the iOS app. GitHub Actions runs every
check that works on Linux. This is the same split the WalkWorthy repo uses.

| Job | Runs on | When |
| --- | --- | --- |
| Core package tests (`Packages/FinalApproachCore`) | GitHub Actions, Linux | Every pull request and push to `main` |
| `ci_scripts` lint and behavior checks | GitHub Actions, Linux | Every pull request and push to `main` |
| App build and unit tests in the simulator | Xcode Cloud | Merge to `main` |
| Archive and internal TestFlight | Xcode Cloud, TestFlight workflow | Merge to `main` |
| Archive, external TestFlight, App Store | Xcode Cloud, Release workflow | Version tag such as `v1.0.0` |
| Backend type check, tests, and template build (`backend/`) | GitHub Actions, Linux | Every pull request and push to `main` |
| Backend deploy to beta | GitHub Actions, Linux | Push to `main` that changes `backend/`, or by hand from the Actions tab |
| Backend deploy to prod | GitHub Actions, Linux | After the beta deploy of the same run passes, and only once the owner approves it |
| Prod holds this backend | GitHub Actions, Linux | Every pull request. It stops an app change while prod is behind `main` |

## Environments

| Stage | Backend | App build | Audience |
| --- | --- | --- | --- |
| beta | AWS beta account | A build made in Xcode, named Approach Beta | The owner's simulator, or a device run from Xcode |
| prod | AWS prod account | Xcode Cloud, named Final Approach | Internal TestFlight on merges to `main`. External TestFlight and the App Store from the Release workflow, created before launch |

The owner chose this split on 2026-11-24. The simulator is where a change is
tried against beta, and the phone runs what users will get. A build made in
Xcode needs no setup to find beta.

Two things follow from it.

- A merge that changes the app sends it to TestFlight at once, while a
  backend change waits for the approval before it reaches prod. So the
  backend goes first. The check named Prod holds this backend, described
  under GitHub Actions below, stops an app change until prod has caught up.
- What is saved from the phone is saved in the prod account. Deleting the
  account in Profile removes it.

The app has one bundle ID, `com.finalapproach.app`, and one App Store Connect
record. The environment is a build setting.

1. `FinalApproach/Config/App.xcconfig` defines `APP_ENVIRONMENT` and
   `APP_DISPLAY_NAME`, and includes `Stages/beta.xcconfig`. So a build made
   in Xcode is a beta build.
2. `FinalApproach/Config/Stages/<stage>.xcconfig` holds the backend for one
   stage, which is the API host, the host the app signs in at, and the id
   the user pool gave the app. `beta.xcconfig` and `prod.xcconfig` both
   exist.
3. Each Xcode Cloud workflow sets the `APP_ENVIRONMENT` environment variable
   to `prod`.
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

### TestFlight workflow

This workflow was first made with the name Beta and with `APP_ENVIRONMENT`
set to `beta`. The variable must now be `prod`. The name is free, and
TestFlight says what it does.

| Setting | Value |
| --- | --- |
| Name | TestFlight |
| Environment, Xcode version | Latest Release |
| Environment, macOS version | Latest Release |
| Environment variable | `APP_ENVIRONMENT` = `prod` |
| Start condition | Branch Changes, branch `main` |
| Start condition, files and folders | Start a build only when files change in `FinalApproach/` or `Packages/` |
| Start condition, auto-cancel builds | On |
| Action 1 | Test, scheme `FinalApproach`, platform iOS Simulator, one recommended iPhone |
| Action 2 | Archive, scheme `FinalApproach`, platform iOS, deployment preparation TestFlight (Internal Testing Only) |
| Post-action | TestFlight Internal Testing, with the internal tester group |

### Release workflow

Create this one shortly before launch. It builds the same prod app as the
TestFlight workflow, from a version tag, and sends it to external testers.

| Setting | Value |
| --- | --- |
| Name | Release |
| Environment variable | `APP_ENVIRONMENT` = `prod` |
| Start condition | Tag Changes, tags beginning with `v` |
| Action 1 | Test, same as the TestFlight workflow |
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
jobs, and `.github/workflows/backend-checks.yml` has one. It also has one job
of its own, which runs on pull requests only.
`.github/workflows/backend-deploy.yml` is separate and deploys the backend to
beta. It is described below.

- **Core package tests** builds and tests `Packages/FinalApproachCore` in the
  official `swift` container image.
- **Xcode Cloud script checks** lints `ci_scripts` with shellcheck and runs the
  post-clone script against a temporary directory.
- **Backend tests and templates** type checks `backend/`, runs its tests, and
  builds the templates for both stages in the official `node` container image.
  It needs no AWS account.
- **Prod holds this backend** keeps the app from getting ahead of prod. It
  is described next.

### Prod before the app

An app change reaches TestFlight as soon as it merges, and that build talks
to prod. A backend change reaches prod only after the owner approves it. The
check named Prod holds this backend keeps the two in order. Its rules are in
`.github/scripts/prod-holds-backend.sh`, and the job runs that script's own
behavior checks first.

- A pull request that changes nothing in `FinalApproach/` or `Packages/`
  starts no app build, so it always passes.
- A pull request may not change the app and `backend/` together. The
  backend change goes in its own pull request first.
- A pull request that changes the app passes only when `backend/` on `main`
  is the same as in the commit prod was last deployed from. The job asks
  GitHub for the newest deploy to the `prod` environment that passed.

When the check stops an app change, approve the waiting Backend deploy run,
or start one with the stage `prod`. After prod has passed, run the failed
check again from the pull request, with Re-run failed jobs.

The check is a rule only once `main` requires it. Under Settings, Branches,
add a rule for `main` that requires status checks to pass, choose Prod holds
this backend, and turn on Require branches to be up to date before merging.
The last setting matters, because the check reads `main` as it was when the
check ran. Without the rule the check still shows red, and a merge is still
possible.

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
2. **Deploy to beta.** Shows what will change, deploys the four backend
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
is the AWS CLI profile `fa_beta` and the prod account is `fa_prod`. Every
workload goes to beta first.

Both stages of the backend are deployed in `us-east-1`. The CDK app takes
the stage from `-c stage=<name>` and the account from the profile in use.
GitHub Actions deploys beta when a backend change reaches `main`, and prod
after the owner approves the same run. The steps are in `docs/backend.md`.
