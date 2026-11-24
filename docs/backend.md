# Backend

The backend is defined with the AWS CDK in TypeScript, in `backend/`. It has
not been deployed. Everything here builds and is tested with no AWS account.

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

## Before the first deploy

These need the person who owns the AWS and Apple accounts. There is one AWS
account for each stage. On the owner's Mac they are the AWS CLI profiles
`fa-beta` and `fa-prod`.

1. Sign in with `aws login --profile fa-beta`.
2. Pick a region. Nothing in the code names one. The plan is `us-east-1`
   unless the owner chooses another.
3. Run `npx cdk bootstrap --profile fa-beta` once in that account and region.
4. Look at what will be created with
   `npx cdk diff --profile fa-beta -c stage=beta`, then deploy with
   `npx cdk deploy --all --profile fa-beta -c stage=beta`.
5. Turn on the Sign in with Apple capability for `com.finalapproach.app` in
   the Apple developer account.
6. After the first deploy, set `API_HOST` in the Xcode Cloud Beta workflow to
   the API's host name, and give the app the user pool id and client id.
7. Add an IAM role that GitHub Actions can assume through OIDC, limited to
   this repository, and then add the deploy workflow. No AWS keys are stored
   in GitHub.

The `prod` stage follows the same steps with `fa-prod` and `-c stage=prod`,
before launch and not sooner.

## Still to come

- The app side, which is Sign in with Apple, upload, and sync.
- A deploy workflow, once the first deploy by hand has worked.
- CloudFront in front of the images, when other users can see photos.
- Telling Apple to revoke the user's tokens when an account is deleted, which
  App Store review asks for. It needs a key from the Apple developer account.
- Alarms and a budget alert.
