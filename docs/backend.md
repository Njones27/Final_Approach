# Backend

The backend is defined with the AWS CDK in TypeScript, in `backend/`. The
`beta` and `prod` stages are both deployed. Everything here builds and is
tested with no AWS account.

## Deployed stages

| Stage | Region | API host | User pool id | App client id |
| --- | --- | --- | --- | --- |
| `beta` | `us-east-1` | `jcpx0b9hg8.execute-api.us-east-1.amazonaws.com` | `us-east-1_IhyFdSJ3t` | `1gcjpq4tk9nbt575ki8bqkn8d6` |
| `prod` | `us-east-1` | `u2680zoug8.execute-api.us-east-1.amazonaws.com` | `us-east-1_fOCqYk7Xe` | `3sf5ptppnd7nvs255nndcfacjt` |

These values ship inside the app, so they are not secrets. The beta stage
was first deployed on 2026-11-24 from the commit that added the backend. The
prod stage was first deployed the same day by the workflow, after the owner
approved the run. A change to `backend/` reaches beta when it reaches
`main`. It reaches prod when the owner approves the same run.

## What it holds

| Stack | Holds |
| --- | --- |
| `FinalApproach-<stage>-Alerts` | The topic that alarms and the budget tell, and the month's budget |
| `FinalApproach-<stage>-Storage` | The DynamoDB table of records with its index of posts open for votes and its index of photos shown at spots, the S3 bucket of images, and the sweeper function |
| `FinalApproach-<stage>-Identity` | The Cognito user pool and the four functions that check Sign in with Apple |
| `FinalApproach-<stage>-Api` | The HTTP API, the functions behind its routes, and the closer that runs on a schedule |
| `FinalApproach-<stage>-Deploy` | The role that lets GitHub Actions deploy the stage. The owner deploys it by hand |

The stage is `beta` or `prod`. Each stage is its own AWS account. What differs
between stages, and every limit that may need tuning, is data in
`backend/lib/stages.ts`.

## Routes

Every route needs a signed in user. A user reaches only their own data. The
voting routes and a spot's page are the exceptions. The voting routes show
another user's photo with nothing else about it. A spot's page shows a graded
photo with what its owner chose to show there.

| Route | What it does |
| --- | --- |
| `PUT /photos/{photoID}` | Saves one photo record. With an image size in the body, it also returns a link to upload that image |
| `GET /photos` | Lists the user's photos, each with a link to its image, and the ids of photos that were deleted |
| `DELETE /photos/{photoID}` | Deletes one photo, its image, and its post |
| `PUT /posts/{photoID}` | Posts one saved photo, which opens it for votes. A second call changes nothing and answers with the first post |
| `GET /posts` | Lists the user's own posts, each with its voting window, how many votes are in, and its score once the grade is final |
| `GET /votes/queue` | Hands the user some photos to vote on, each as a random id and a link to the image |
| `PUT /votes/{postID}` | Counts the user's vote on one post, a whole number of stars from 1 to 5 |
| `PUT /posts/{photoID}/spot` | Shows one of the user's posted photos at a listed spot, with its aircraft type and airline |
| `DELETE /posts/{photoID}/spot` | Takes the photo off its spot |
| `GET /spots` | Lists the spots the app shows, grouped by airport. The list is the same for every user |
| `GET /spots/{spotID}/photos` | Lists the graded photos shown at one spot, best first |
| `DELETE /account` | Deletes every image and record the user has, and their sign in |

A refusal carries a `message`. It also carries a `code` when the app acts on
it, because two refusals can share a status. The codes are `notSignedIn`,
`photoDeleted`, `accountDeleted`, `photoNotSaved`, `imageHasLocation`,
`alreadyVoted`, `votingClosed`, `ownPost`, `notPosted`, and `unknownSpot`.
The app reads the code and never the message.

A photo record is the app's own saved photo, kept as it is and returned only
to its owner. The backend does not read inside it yet. It can hold where the
photo was taken. A route that shows a photo to another user builds its
answer from named fields and never sends this record. A spot's page, under
Spots below, is the one route that says where a photo was taken, and only
for a photo whose owner put it there.

## Posting

A post puts one photo in front of other users for their votes. It is the
first record another user can reach, so it is built to give nothing away.

- Posting never asks how the photo did in the technical check, and the
  backend holds no result of that check. The check is advice to the
  photographer. Every posted photo goes to the vote, and the votes alone
  will set its grade. `docs/build-plan.md` has the decision under Grading.
- A post holds the photo's id, a random id of its own, when it was posted,
  and when its voting window ends. It holds no location, no name, and
  nothing from the photo record. A voter will know a post only by its
  random id, which does not name the owner. The owner can later show the
  post at a spot, which is a separate step described under Spots.
- A post is made only for a photo whose record and image have both arrived.
  The app syncs first and posts second. `photoNotSaved` says to do that.
- The image is checked before every post, in
  `backend/src/posts/imageCheck.ts`. An Exif block with a GPS directory, an
  XMP block that names a GPS position, or an IPTC block, which can name a
  city, stops the post with `imageHasLocation`. An Exif block that cannot
  be read stops it too. The app saves its images with no metadata, and this
  check makes the backend hold the same line, so an undisclosed photo
  cannot give its place away through its image. It runs for every photo,
  because the image is never where a place is meant to be shown.
- A photo is posted once. There is no route to take a post back, because a
  photo that could be posted again would start its votes again. Deleting
  the photo takes its post down.
- The voting window is `votingWindowHours` in the stage settings, 72 hours.
  Changing it moves the end of the window for photos posted from then on.
- A post sits in its owner's partition of the table. An open post also
  carries `votingKey`, which puts it in the `Voting` index. That index is
  how the voting queue finds open posts across users.

Two limits are known. The check reads the blocks in front of the picture
data, which is where cameras and editors write metadata, and not anything
hidden after it. And an owner can upload a new image for a photo after it
is posted. Both take a changed app to do, and both give away only the
owner's own place.

## Voting and the grade

The owner decided on 2026-11-24 that the votes alone set a photo's grade.
The rules are in `backend/src/votes/standing.ts`, and every number in them
is data in `backend/lib/stages.ts`.

- A vote is a whole number of stars from 1 to 5 (`voteScaleMax`).
- A user has one vote on a post, and it cannot be changed. A user cannot
  vote on their own photo, and never sees it in their queue.
- A post takes votes until its window has ended and it has 5 votes
  (`minVotesToFinalize`). A post that reaches the end of its window short of
  votes stays open, and the vote that brings it to the minimum closes it.
- The grade is the weighted average of the votes, stretched so that all one
  star is 0 and all five stars is 100, and rounded to a whole number.
  Nothing else takes part in it.
- Every vote has a weight of 1 today. The weight is kept on each vote and
  in the post's totals, so reputation can change it later without a change
  to what is stored.

Voting is blind in both directions.

- The queue gives a voter the image and the post's random id. It gives no
  name, no place, no count, no score, and no closing time. Casting a vote
  answers with the vote and nothing about how the photo is doing.
- The owner sees how many votes are in while voting is open. The score
  appears only once the grade is final.
- A vote is kept under its voter and names the post by its random id only,
  so a voter's records never say whose photo they voted on.

How it works.

- The queue reads the `Voting` index on from a random id and wraps around
  at the end. Post ids are random, so every open post has the same chance
  of being near the front. It reads up to 50 posts (`votingQueueReadLimit`),
  drops the voter's own, the ones they voted on, and the ones whose voting
  has ended, and hands out up to 10 (`votingQueueSize`).
- A vote is one transaction. It writes the vote, adds to the totals on the
  post, and checks that the post is still open, so two votes at once cannot
  both be the last one.
- The closer runs every 15 minutes (`closerMinutes`). It writes the final
  score on each post whose voting has ended and takes the post out of the
  index. A post stops taking votes by the rules alone, so nothing depends
  on when the closer runs. A score that was written down stands, even if
  the settings change later.

What deleting does to votes.

- Deleting a photo removes its post, so it leaves the queue and takes no
  more votes. The votes cast on it stay with their voters. Each holds a
  random id and a number of stars and nothing of the photo.
- Deleting an account removes the user's votes with their other records.
  The totals on the posts they voted on keep what was already counted,
  which is a sum that names nobody.

Known limits.

- The link to an image has the owner's id and the photo's id in its path.
  Both are random ids that the app never shows, and no name can be found
  from them. CloudFront in front of the images, listed under Still to come,
  removes this.
- Every open post is in one partition of the index, and the closer reads
  all of it on each run. That is fine for thousands of open posts and needs
  another look before many more.
- Nothing stops one person from voting with two accounts.

## Spots

A spot is a place to photograph aircraft from. The owner decided that spots
are chosen by hand at launch, so there is no route that adds one.

- The list is data in `backend/src/spots/catalog.ts`. A spot has an id, a
  name, a summary, a pin, access notes, local rules, and runway notes. It
  sits under its airport, which has a code, a city, and a pin.
- A spot is added only once someone has checked it. It must be on ground
  the public may use, and its local rules must say what the airport asks of
  photographers. A listing never sends anyone into a restricted area.
- The list is empty until the owner supplies the first real spots. The
  spots in the app's sample data are made up and are not published.
- A deploy changes the list, with no release of the app. The list is part
  of the function's code, so the function reads no table and no image and
  has no access to either.
- `problemsIn` in the same file says everything wrong with a list, such as
  a spot listed twice, a missing local rule, or a pin far from its airport.
  The tests run it on the list that ships, so a bad listing stops a pull
  request.
- A spot's id never changes once it ships, because photos will name their
  spot by it.
- `GET /spots` answers with `airports`, each with its `spots`. The answer
  is built from named fields and says nothing about any user or photo.

A spot's page shows graded photos taken there. The owner decided on
2026-11-24 that a photo shows with its grade, its aircraft type, and its
airline, and with no photographer and no registration.

- A photo is on a spot's page only because its owner put it there. Posting
  alone never does it. `PUT /posts/{photoID}/spot` takes a `spotID`, an
  `aircraftType`, and an `airline`, and keeps those three things and nothing
  else that is sent. The app sends it only for a photo whose owner disclosed
  its place. An undisclosed photo is never sent, so it is on no page.
- The spot must be listed, or the answer is `unknownSpot`. The photo must be
  posted, or the answer is `notPosted`. The two lines of text are trimmed,
  and each is plain text of up to 80 characters (`shownTextMaxLength`).
- `DELETE /posts/{photoID}/spot` takes the photo off its spot and removes
  everything that was shown. The app sends it when the owner takes the
  photo off the page, and when a photo that is on a page turns out to be
  undisclosed. Sending the first route again replaces what was shown.
- The owner's `GET /posts` says where each photo is shown, under `shownAt`,
  so the app can keep the backend in line with the owner's choice.
- A photo appears only once its grade is final. The post carries `spotKey`
  while it is shown and `finalScore` once it is graded, and the `Spot` index
  holds a record only when it has both. So nothing has to move a photo onto
  the page or off it. Deleting the photo or the account removes it like any
  record.
- `GET /spots/{spotID}/photos` reads that index backwards, so the best
  photo is first, and hands out up to 30 (`photosPerSpot`). Each photo is
  the post's random id, a link to the image, the score, and the type and
  airline when the owner gave them. The owner's id and the photo's id are
  used to sign the link and are not sent as fields.
- The Spots function may read that one index and sign links to images. It
  cannot read the table of every user's records, and it writes nothing.

Known limits.

- The link to an image has the owner's id and the photo's id in its path,
  as it does for voting. Both are random ids. On spot pages they can show
  that two photos have the same owner, and nothing about who that is.
  CloudFront in front of the images removes this.
- A registration is never shown, because the backend does not hold the
  list of blocked registrations yet. The type and airline are the owner's
  own text, and the app leaves them out for a blocked aircraft.
- A spot's page holds its 30 best photos and has no second page.

## Sign in

The app shows Apple's own sign in sheet and gets an identity token. The user's
name in the pool is Apple's id for them. Test accounts are the one exception
and are described under Test accounts below.

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

### Test accounts

A second account is needed to try voting and spot pages, because nobody is
shown their own photos to vote on. App Review also asks for an account it can
use. So a stage whose `testAccountSignIn` setting is true lets a test account
sign in with a name and a password. Both stages have it on.

Nobody can sign up for a test account. A sign up is refused without Apple's
token for the same name, so the only way to make one is by hand, as the
owner, with the two commands below. The first makes the account and the
second gives it a password that does not have to be changed at the first
sign in. Use a long random password, above all on prod.

```sh
aws cognito-idp admin-create-user --profile fa_beta --region us-east-1 \
  --user-pool-id <pool id> --username test-one --message-action SUPPRESS
aws cognito-idp admin-set-user-password --profile fa_beta --region us-east-1 \
  --user-pool-id <pool id> --username test-one --password '<password>' --permanent
```

The app signs a test account in with one `InitiateAuth` request that uses
the `USER_PASSWORD_AUTH` flow. From there a test account is a user like any
other. Its photos, posts, and votes are real ones, so on prod its votes count
toward real grades. Deleting the account in the app removes it from the pool
too, and it must be made again by hand.

A sign up through Sign in with Apple still carries a password, because the
pool asks for one. The app makes it at random and keeps it nowhere. A changed
app could choose that password for its own new account, and could then sign
in to that one account without Apple. It gains nothing else, since a sign up
is accepted only with Apple's token for that same account.

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

A post keeps no copy of the image. It points at the photo's own image, so
there is no second place to clear. Deleting a photo removes its post in the
same step as the photo's record, so a post never outlives its photo. Deleting
an account removes its posts with every other record in the user's partition.
The `Voting` index follows the table, so a removed post leaves the index too.

Two limits are known. The table can be restored to any point in the last 35
days, so a deleted record stays in those backups until they age out, which
the privacy policy should say. Deleting an account runs inside one request of
29 seconds, so a very large account may need the app to send the request more
than once.

## Sync in the app

The pieces below make up the app's side. They run once someone is signed
in, from the Account section of the Profile screen.

- The rules are pure and live in the core package, in `PhotoSync.swift`.
  `SyncPlan.actions` takes what the device holds, what the backend listed,
  and a small ledger the device keeps between syncs, and returns the steps to
  run. `SyncLedger` records what both sides last agreed on.
- The code that talks to the routes is in the app, in `Services/Backend/`.
  `PhotoBackend` is the protocol, `HTTPPhotoBackend` is the real one, and
  `SamplePhotoBackend` keeps everything in memory for previews and tests.
- `SyncEngine`, in the same folder, carries the steps out against the
  collection on the device. It records each step in the ledger as it
  finishes, so a sync that stops partway picks up where it stopped. The
  ledger is saved with the library on the device.
- Signing in is in the same folder. `IdentityService` is the protocol,
  `CognitoIdentityService` follows the steps under Sign in above, and
  `SampleIdentityService` stands in for previews and tests. It needs no AWS
  library, because each step is one plain request.
- `AccountSession`, in `Models/`, holds who is signed in and hands out the
  access token the routes need. It gets a new token shortly before the old
  one runs out, and many callers at once share one request for it. When the
  pool says the session has ended, the app is signed out.
- The session is kept in the Keychain through `SessionStore`, on this device
  only, so it is not copied to a backup or to another device. Signing out
  removes it first and then tells the pool to end it.
- `SyncCoordinator`, in `Models/`, decides when a sync runs. One runs each
  time the app comes to the front, and one runs shortly after the user adds,
  edits, or deletes a photo. Changes made together go in one sync. A sync
  asked for while one runs makes that one run once more. The wait after a
  change is data in `SyncPacing`.
- `AccountSection`, in `Features/Profile/`, shows Apple's sign in button,
  the state of the last sync, and a way to sign out. A build with no backend
  leaves it out. Signing in sends the photos already on the device to the
  account. Signing out leaves them on the device and sends nothing more.
- A test account signs in from the same section. Use a test account opens
  `TestAccountSignInView`, a sheet that asks for the name and the password
  and sends them in one request. It never makes an account. The password is
  kept nowhere, and a failed try clears it from the sheet. The saved sign in
  remembers that it is a test account, so Profile can say how the user
  signed in. From there a test account syncs, posts, and votes like any
  other user.

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
- A change the user makes while a sync is running stands. A photo deleted
  while it is being sent is removed from the backend on the next sync, and a
  photo edited while its newer copy is being fetched keeps the edit.
- One photo that fails does not stop the rest. It is tried again on the next
  sync. A sync stops only when no one is signed in, the account was deleted,
  or the backend cannot be listed.
- The ledger belongs to one account. When another user signs in on the same
  device, the ledger is started again for them. A delete the first account
  is still owed is set aside, and it is sent when that user next signs in
  on the device. It is never sent to the other user's account.

Deleting the account from the app follows three steps, in this order.

1. The request is saved in the Keychain, next to the tokens it needs. If it
   cannot be saved, nothing is removed and the user is told to try again.
2. Every photo and image is removed from the device. A sync that is running
   stops and puts nothing back.
3. The backend is told. When the backend fails partway, the request is sent
   again at once, a few times. With no network the delete stays owed, and it
   is sent each time the app comes to the front until it goes through.

While a delete is owed nothing syncs, and no one can sign in or out, because
the delete needs the tokens. If the sign in itself stops working in that
time, the delete counts as done. That is what happens when the first request
did reach the backend, which removes the user from the pool.

One limit is known on the app's side. A second device that still holds the
user's photos keeps them when the account is deleted from the first one. Its
sign in ends by itself within the hour. If the same person signs in there
again later, those photos are sent to the new account. Closing this needs
the backend to remember a deleted account, which it does not do today.

## Posting in the app

Posting sits on top of sync. A photo is synced first and posted second,
because the backend posts only a photo whose record and image it holds.

- `PostBackend`, in `Services/Backend/`, is the protocol for the two post
  routes. `HTTPPostBackend` is the real one and `SamplePostBackend` keeps
  posts in memory for previews and tests. A request to post sends the
  photo's id in the path and no body, so nothing about the photo is sent
  again. `SignedInAPI` is the caller every signed in route shares.
- `SyncCoordinator.post` runs a sync, waits for it, and then posts. A sync
  that was already running is asked to run once more, and the post waits for
  that one.
- What the backend says about a post is a `PostStanding`, in the core
  package. It holds when the photo was posted, when its window ends, how
  many votes are in, and the score once it is final.
- The standings are kept with the collection, apart from the photo's own
  record. A new vote is then never an edit to the photo, so it starts no
  upload. They are saved with the library on the device, and every sync
  asks the backend for them again. The backend's list replaces what was
  heard before, so a photo it lists no post for is not posted.
- The screens read `CollectionModel.progress(for:)`, which is logged,
  voting, or graded. A photo the user posted takes it from its standing. A
  sample photo takes it from its own saved status.
- The fewest votes a grade needs comes from the backend with the list of
  posts, so it can change with no release.
- The photo screen offers the post in a build that has a backend. The button
  reads Post for votes, or Post anyway when the technical check has ideas.
  The check never stands in the way. The user confirms once, because a post
  cannot be taken back.
- Deleting a photo or the account forgets its standing on the device. The
  backend removes the post with the photo.

## Voting in the app

The Vote screen shows photos other people posted, one at a time, and takes
a vote in stars.

- `VoteBackend`, in `Services/Backend/`, is the protocol for the two vote
  routes and for fetching an image from its link. `HTTPVoteBackend` is the
  real one and `SampleVoteBackend` keeps votes in memory for previews and
  tests. The image is fetched with no token, because the link carries its
  own permission. Nothing fetched is kept on the device.
- `VotingModel`, in `Models/`, runs the screen. It asks for the queue, shows
  one photo, casts the vote, and moves on. All it holds about a photo is the
  post's random id and the image, so the screen has nothing else to show.
- A vote takes two taps. The user picks stars and then presses Cast vote,
  because a vote cannot be changed once it is cast.
- The top of the scale comes from the backend with the queue, so it can
  change with no release. The screen ignores a scale it has no room for.
- A photo the user skips gets no vote. The backend may hand it out again,
  and the model does not show it twice on one visit.
- A vote the backend cannot count, such as a second vote or a vote on a
  closed post, moves on to the next photo. A vote that did not reach the
  backend keeps the photo on the screen for another try.
- A link to an image works for a few minutes. A post whose link ran out is
  dropped, and the queue is asked for again, which gives new links. The
  queue is asked for at most twice in one go.
- A signed out user is asked to sign in. Signing out, or a different user
  signing in, starts the screen over.
- A build with no backend keeps the sample set on the same screen.

## Spots in the app

The Spots screen shows the backend's spots on a map, and each spot has a
page with the graded photos people chose to show there.

- `SpotBackend`, in `Services/Backend/`, is the protocol for the list of
  spots, for one spot's photos, and for fetching an image from its link.
  `HTTPSpotBackend` is the real one. `SampleSpotBackend` keeps the sample
  spots and a few sample photos in memory, for previews, for tests, and for
  a build with no backend.
- `SpotsModel`, in `Models/`, asks for the list when the app opens, when
  the Spots screen appears, and when the sign in changes. It hands the list
  to `CollectionModel`, which uses it to say which spot a photo was taken
  from. A build with a backend starts with no spots, because the sample
  spots are made up. A list that cannot be fetched leaves the one in hand.
- The backend lists spots for a signed in user, so a signed out user is
  asked to sign in. While no spot is listed, the card under the map says so.
- A photo is linked to the spot it was logged with while that spot is
  listed, and otherwise to the listed spot nearest to where it was taken.
  So a photo logged before its spot was listed still finds it.
- A spot's photos are asked for each time the spot takes the card or its
  page opens, because a link to an image works for a few minutes. The model
  owns each request, so a screen that goes away does not cut one off.
- All the app holds about another person's photo is the post's random id,
  the image, the grade, and the aircraft type and airline its owner chose
  to show. The tier is worked out from the grade with the app's thresholds.
  There is no name, registration, or position to show.
- The image is fetched with no token and made small for the screen, at most
  1,200 pixels on its longest side. The full image is never kept. The small
  copies live in memory only. A copy goes when its photo leaves the page,
  and every copy goes when the user deletes one of their own photos,
  deletes their account, or signs out, because a page may show the user's
  own photo.

Which page one of the user's photos is on is the owner's choice.

- A photo is logged with "Show the spot to other people" on or off. A photo
  logged with it off is undisclosed, and the app never sends it to a page.
- Posting a disclosed photo taken at a listed spot also puts it on that
  spot's page. The screen says so before the post, and the page shows the
  photo only once it is graded. The post stands even when the page could
  not be reached.
- A photo posted before spots had pages was posted with the promise that
  nobody sees where it was taken. Nothing puts such a photo on a page by
  itself. Its own screen offers "Show it on the spot's page", and the owner
  decides.
- The photo's own screen says whether it is on a page and offers "Take it
  off the spot's page". The post and its grade stay.
- The app sends the spot's id, the aircraft type, and the airline. It sends
  no position and no registration. For a blocked aircraft it sends neither
  the type nor the airline. A line the backend would refuse, such as one
  over 80 characters, is left out, by `ShownText` in the core package.
- `GET /posts` says where each photo is shown, and the app saves that with
  the library. After each sync the app brings the pages in line. A photo
  whose aircraft details changed has the words beside it replaced, and an
  undisclosed photo found on a page is taken off. A sync never puts a photo
  on a page it was not on.

Known limits.

- The list of spots is kept in memory. A photo logged right after the app
  opens with no network has no spot until the list arrives, and then finds
  it by where it was taken.
- A photo on a page cannot be opened larger yet.
- A deleted photo can stay on a page until the delete reaches the backend,
  which a sync does a few seconds later.

## Alarms and the budget

Each stage tells its owner when something is wrong. Everything goes to one
topic in the stage's `Alerts` stack, and the owner gets it as an email.

| Alarm | Goes off when |
| --- | --- |
| Each function but the sign up check, ten in all | The function fails once in five minutes |
| The sign up check, `PreSignUp` | It fails 20 times in five minutes |
| The API | It answers with a server error once in five minutes |
| The budget | The month has cost half of the budget, all of it, or is on course to go over |

- The sign up check refuses a sign up by failing, and anyone can send a bad
  sign up. So one refusal is not news, and many at once may be someone
  trying the door.
- Every function is made by `backendFunction` in `backend/lib/functions.ts`,
  which adds the alarm. A function added later is watched with nothing more
  to write.
- A period with no traffic is quiet and sets nothing off.
- The budget is 10 US dollars a month for beta and 20 for prod. An idle
  stage costs close to nothing, so either message means something changed.
- Every number here is data in `backend/lib/stages.ts`.

An alarm's message names the function. Its log group, in CloudWatch, says
what failed.

### Getting the messages, set up once for each account

The topic has no subscriber in the code. The owner's address is private and
this repository is public, so the owner subscribes by hand. Run this once
with `fa_beta` and once with `fa_prod`, with the address in place of the
last line's placeholder.

```sh
profile=fa_beta
stage=beta
topic="$(aws cloudformation describe-stacks --stack-name "FinalApproach-${stage}-Alerts" \
  --profile "$profile" --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='AlertsTopicArn'].OutputValue" --output text)"
aws sns subscribe --topic-arn "$topic" --protocol email \
  --profile "$profile" --region us-east-1 \
  --notification-endpoint ADDRESS
```

AWS then sends an email with a link, and the messages start once the link
is opened. Until then an alarm still goes off, and nobody is told.

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

## Deploying from GitHub

`.github/workflows/backend-deploy.yml` deploys the Alerts, Storage, Identity,
and Api stacks when a push to `main` changes `backend/`. Beta goes first. Prod
follows in the same run after the owner approves it. The owner can also start
a run by hand from the Actions tab. It stores no AWS keys. `docs/ci-cd.md`
describes the jobs and how they sign in.

### Beta, set up once

Beta needs two things set up once, by the person who owns the AWS account.
Both are done.

1. Deploy the role it uses, with
   `npx cdk deploy FinalApproach-beta-Deploy --profile fa_beta -c stage=beta`.
   The stack makes the account trust GitHub's tokens, and makes one role,
   `FinalApproach-beta-GitHubDeploy`. If the account already trusts GitHub's
   tokens for another project, the deploy stops and changes nothing, and the
   stack must use the existing provider.
2. Save the stack's `DeployRoleArn` output as the repository variable
   `BETA_DEPLOY_ROLE_ARN`, under Settings, Secrets and variables, Actions,
   Variables. It is a variable and not a secret, because it only names the
   role.

### Prod, set up once

Prod is deployed by the same workflow, after an approval. The steps below
were done on 2026-11-24, and they are kept here for a new account. Without
them the prod job is left out of every run. Do them in this order, because
the prod role trusts every job that names the `prod` environment, and only
the environment's settings keep other branches out and ask for the approval.

1. On GitHub, open Settings, Environments, and make an environment named
   `prod`. Turn on Required reviewers and add the owner. Leave Prevent self
   review off, because the owner is the only reviewer. Under Deployment
   branches and tags choose Selected branches and tags, and add `main`.
2. Sign in to the prod account with `aws login --profile fa_prod` and set
   `AWS_REGION=us-east-1`. Start from a folder that still exists, such as
   the home folder. A Terminal window left in a deleted folder fails at the
   first `git` or `npx` command.
3. Bootstrap the account once, with
   `npx cdk bootstrap aws://<account id>/us-east-1 --profile fa_prod -c stage=prod`.
4. Deploy the role, with
   `npx cdk deploy FinalApproach-prod-Deploy --profile fa_prod -c stage=prod`.
   It makes the account trust GitHub's tokens, and makes one role,
   `FinalApproach-prod-GitHubDeploy`.
5. Save the stack's `DeployRoleArn` output as the repository variable
   `PROD_DEPLOY_ROLE_ARN`. From then on every run goes on to prod and waits
   for the approval.
6. Start the first deploy from the Actions tab. Choose Backend deploy, Run
   workflow, and the stage `prod`. Approve it when GitHub asks. The deploy
   step prints the API URL, the user pool id, and the app client id.
7. Put those three values in the table at the top of this page and in a new
   `FinalApproach/Config/Stages/prod.xcconfig`, shaped like `beta.xcconfig`.

### What the roles can do

Each role can do one thing, which is to take on the roles the CDK bootstrap
made for deploying. Those end in CloudFormation's own role, which the
bootstrap gives full access to the account. So a change that reaches `main`
can change anything in the beta account. That is the usual trade for
deploying on a merge. The same change can reach the prod account only after
the owner approves the run, which is why prod has the approval and beta does
not.

The workflow never deploys a Deploy stack. A change to who may deploy is
made by hand, with the command that first deployed the stack.

The stage settings name the owner and the repository, and then a branch or a
GitHub environment, in `deployFrom` in `backend/lib/stages.ts`. A stage
without it gets no role. GitHub writes the owner and the repository into its
token by name and by id, as in
`repo:Njones27@153565100/Final_Approach@1468200614:ref:refs/heads/main` for
beta and
`repo:Njones27@153565100/Final_Approach@1468200614:environment:prod` for
prod, and each role matches its text exactly. A job that names an environment
gets the second form, which does not say which branch it runs for. That is
why the `prod` environment itself must allow only `main`. The ids never change, so a repository
that later takes the same name cannot deploy. If the sign in step of the
workflow is turned away, the account's CloudTrail event for
`AssumeRoleWithWebIdentity` shows the subject GitHub sent, under
`userIdentity.userName`.

## Deploying by hand

A deploy needs the person who owns the AWS account. There is one AWS account
for each stage. On the owner's Mac the beta account is the AWS CLI profile
`fa_beta`, and the prod account is `fa_prod`.

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
The stage is needed because the CDK runs the app even for a bootstrap. Both
accounts are already bootstrapped.

The `prod` stage follows the same steps with its own profile, `fa_prod`, and
`-c stage=prod`. A deploy by hand is for the first setup and for emergencies.
The usual way to prod is the workflow, after an approval.

## Before the app can sign in

One thing needs the person who owns the Apple developer account, which is to
turn on the Sign in with Apple capability for `com.finalapproach.app`, under
Certificates, Identifiers & Profiles, Identifiers.

The app asks for the capability in `FinalApproach/Config/FinalApproach.entitlements`,
which `App.xcconfig` names. An archive is signed for an App ID, so a build
for TestFlight fails to sign while the App ID does not have the capability.
A simulator build is not affected.

The app finds each backend by itself. The values in the table above are in
`FinalApproach/Config/Stages/beta.xcconfig` and `prod.xcconfig`. A build
made in Xcode takes the beta values, and a build from Xcode Cloud, which
goes to TestFlight, takes the prod values. `docs/ci-cd.md` describes how. A
change to those values in a deploy must be copied into the stage's file.

## Still to come

- The first real spots in the list, which the owner supplies.
- A way to open a photo on a spot's page larger, and a way to change
  whether a logged photo's spot shows.
- Reputation, which gives a voter whose votes land near the final grades
  more weight. It needs a way to find a post's votes when the post closes.
- A filter that keeps a photo with no aircraft out of the voting queue. It
  is planned and not decided.
- A first real sign in on an iPhone, from a TestFlight build against prod.
  Everything up to here is tested against stand ins for Apple and the
  backend.
- CloudFront in front of the images, when other users can see photos.
- Telling Apple to revoke the user's tokens when an account is deleted, which
  App Store review asks for. It needs a key from the Apple developer account.
