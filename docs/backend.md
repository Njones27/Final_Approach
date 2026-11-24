# Backend

The backend is defined with the AWS CDK in TypeScript, in `backend/`. The
`beta` stage is deployed and `prod` is not. Everything here builds and is
tested with no AWS account.

## Deployed stages

| Stage | Region | API host | User pool id | App client id |
| --- | --- | --- | --- | --- |
| `beta` | `us-east-1` | `jcpx0b9hg8.execute-api.us-east-1.amazonaws.com` | `us-east-1_IhyFdSJ3t` | `1gcjpq4tk9nbt575ki8bqkn8d6` |

These values ship inside the app, so they are not secrets. The beta stage
was first deployed on 2026-11-24 from the commit that added the backend. A
change to `backend/` reaches beta only when it is deployed again.

## What it holds

| Stack | Holds |
| --- | --- |
| `FinalApproach-<stage>-Storage` | The DynamoDB table of records, the S3 bucket of images, and the sweeper function |
| `FinalApproach-<stage>-Identity` | The Cognito user pool and the four functions that check Sign in with Apple |
| `FinalApproach-<stage>-Api` | The HTTP API and the functions behind its routes |

The stage is `beta` or `prod`. Each stage is its own AWS account. What differs
between stages, and every limit that may need tuning, is data in
`backend/lib/stages.ts`.

## Routes

Every route needs a signed in user. A user reaches only their own data.

| Route | What it does |
| --- | --- |
| `PUT /photos/{photoID}` | Saves one photo record. With an image size in the body, it also returns a link to upload that image |
| `GET /photos` | Lists the user's photos, each with a link to its image, and the ids of photos that were deleted |
| `DELETE /photos/{photoID}` | Deletes one photo and its image |
| `DELETE /account` | Deletes every image and record the user has, and their sign in |

A refusal carries a `message`. It also carries a `code` when the app acts on
it, because two refusals can share a status. The codes are `notSignedIn`,
`photoDeleted`, and `accountDeleted`. The app reads the code and never the
message.

A photo record is the app's own saved photo, kept as it is and returned only
to its owner. The backend does not read inside it yet. It can hold where the
photo was taken. A later route that shows a photo to another user must build
its answer from named fields and leave the location out of an undisclosed
photo. It must never send this record as it is.

## Sign in

The app shows Apple's own sign in sheet and gets an identity token. The user's
name in the pool is Apple's id for them. There are no passwords in use.

1. On a first sign in the app calls `SignUp` with the token as validation
   data. The pre sign up function lets the user in only when the token is
   Apple's, is for this app, is fresh, and names the same user.
2. The app calls `InitiateAuth` with the custom flow, and answers the one
   challenge with the token. The pool issues its own tokens when the token
   passes the same checks.
3. The app keeps the pool's refresh token, so Apple's sheet is not shown
   again until the user signs out.

The token checks are in `backend/src/auth/appleToken.ts`. The token is not
tied to one sign in attempt, because the app learns the user's name from the
token itself. A copied token is of use only until it reaches the age limit in
the stage settings, which is ten minutes.

## Deleting

Deleting a photo or an account must remove the stored images. Four things
make that hold.

- The bucket keeps no old versions, so a deleted image is gone.
- A delete writes its marker first and removes images second. A deleted
  photo's marker turns away a later save of the same photo, so another device
  cannot bring it back. A deleted account's marker turns away every later
  write, and it expires by itself after every token issued before the delete
  has run out.
- An upload link works for a few minutes, so an image can arrive after its
  photo or account was deleted. The sweeper runs on every upload and removes
  an image that has nothing to belong to.
- A delete that fails partway can be sent again and picks up where it stopped.

Two limits are known. The table can be restored to any point in the last 35
days, so a deleted record stays in those backups until they age out, which
the privacy policy should say. Deleting an account runs inside one request of
29 seconds, so a very large account may need the app to send the request more
than once.

## Sync in the app

The app's side is being built in steps. Two pieces are in place, and nothing
calls them yet.

- The rules are pure and live in the core package, in `PhotoSync.swift`.
  `SyncPlan.actions` takes what the device holds, what the backend listed,
  and a small ledger the device keeps between syncs, and returns the steps to
  run. `SyncLedger` records what both sides last agreed on.
- The code that talks to the routes is in the app, in `Services/Backend/`.
  `PhotoBackend` is the protocol, `HTTPPhotoBackend` is the real one, and
  `SamplePhotoBackend` keeps everything in memory for previews and tests.

The rules a sync follows.

- A delete always wins. A photo deleted on any device is removed everywhere
  and is never sent or fetched again.
- A photo deleted on the device stays in the ledger as a pending delete until
  the backend confirms it. A failed request cannot leave a deleted photo's
  image on the backend.
- When a record changed on the device and on the backend since they last
  agreed, the device's copy is sent, because it holds the edit the user just
  made.
- The device tells an edited record from an untouched one by a hash of the
  record. It tells a changed backend record by the `updatedAt` the backend
  returns.
- A record this version of the app cannot read is left alone. A newer
  version of the app most likely saved it.
- A sample photo ships with the app and is never sent.

## Build and test

```sh
cd backend
npm ci
npm run typecheck
npm test
npx cdk synth --quiet -c stage=beta
```

The tests use Node's own test runner and run the TypeScript files directly,
so there is no build step. Node 22 is needed. GitHub Actions runs the same
four commands on every pull request.

## Deploying by hand

A deploy needs the person who owns the AWS account. There is one AWS account
for each stage. On the owner's Mac the beta account is the AWS CLI profile
`fa_beta`.

1. Sign in with `aws login --profile fa_beta`.
2. Use `us-east-1`. Nothing in the code names a region, so set
   `AWS_REGION=us-east-1` in the shell.
3. Look at what will change with
   `npx cdk diff --profile fa_beta -c stage=beta`.
4. Deploy with `npx cdk deploy --all --profile fa_beta -c stage=beta`.
5. Check it. `GET /photos` with no sign in answers 401, and a second
   `cdk diff` shows no differences.

A new account is bootstrapped once before its first deploy, with
`npx cdk bootstrap aws://<account id>/us-east-1 --profile <profile> -c stage=<stage>`.
The stage is needed because the CDK runs the app even for a bootstrap. The
beta account is already bootstrapped.

The `prod` stage follows the same steps with its own profile and
`-c stage=prod`, before launch and not sooner.

## Before the app can sign in

These need the person who owns the Apple and App Store Connect accounts.

1. Turn on the Sign in with Apple capability for `com.finalapproach.app` in
   the Apple developer account.
2. Set `API_HOST` in the Xcode Cloud Beta workflow to the beta API host in
   the table above.

## Still to come

- The rest of the app side. That is Sign in with Apple, the engine that runs
  the sync steps, telling the backend when a photo or the account is deleted,
  and the screens for signing in.
- A deploy workflow. It needs an IAM role that GitHub Actions can assume
  through OIDC, limited to this repository, so no AWS keys are stored in
  GitHub.
- CloudFront in front of the images, when other users can see photos.
- Telling Apple to revoke the user's tokens when an account is deleted, which
  App Store review asks for. It needs a key from the Apple developer account.
- Alarms and a budget alert.
