# Build plan

This page records the decisions made on top of `docs/design-context.md` and the
order of work. The design context stays the source for product requirements.

## Decisions

| Topic | Decision |
| --- | --- |
| Platform | iOS only, SwiftUI, iOS 26 minimum, iPhone only for now |
| Backend | AWS, defined with CDK in TypeScript |
| CI/CD | Xcode Cloud for the app, GitHub Actions for the core package and the backend. See `docs/ci-cd.md` |
| Identity | Final Approach, bundle ID `com.finalapproach.app` |
| Voting | 1 to 5 scale, 72 hour window, 5 vote minimum |
| Grading | The technical check coaches before posting and never gates or lowers a grade. Votes alone set the public grade. See Grading below |
| Spots | Curated at launch |
| Reuse | Grading logic lives in `Packages/FinalApproachCore` so a car photography version could share it |
| Order of work | UI design first, then one small milestone at a time |
| Look | Darkroom. A true black ground in dark mode and white in light mode, photos first, one condensed face for numbers. See the next section |
| Appearance | Follows the iPhone setting, with a System, Light, or Dark choice in Profile |

## Interface

The look is called Darkroom. The rules below apply to every screen.

- Four tabs hold the four sections, which are Collection, Spots, Vote, and
  Profile. Adding a photo is an action, so it is a button on Collection and
  not a tab. The tab bar stays in place on every screen, pushed ones too.
- The system tab bar, toolbars, and sheets are used as they are, so they pick
  up Liquid Glass on iOS 26 with no custom drawing.
- The system font carries the interface. Barlow Condensed is bundled and used
  only for grade numbers, registrations, and counts.
- Colors live in `Design/Theme.swift`. Each one has a dark and a light value
  under one name, so no screen branches on the color scheme. Labels that sit
  on a photo stay white in both appearances.
- A grade is shown on a scale that is split at the tier thresholds, so the
  distance to the next tier is visible. Feedback is a short list of fixes,
  each with the points it is worth.
- Motion is short and eases out, and its timings live in
  `Design/Motion.swift`. A photo grows out of its collection tile and shrinks
  back into it. The grade marker travels up the tier scale, meters fill from
  the top down, the next photo to vote on slides in, and the grid slides to a
  new order. The system tab view swaps tabs with no motion, so each tab's
  content fades in and slides from the side its tab sits on. With Reduce
  Motion on, anything that travels fades or stays still.
- The tier thresholds of 50, 65, and 80, the passing score of 75 for one
  check, and the points for each fix on the sample photos are placeholders in
  `SampleData`. They are passed in as data and are not decided yet.

Two controls from the mockups wait for the milestone that gives them something
to do. "Pick a different aircraft" on the Add screen arrives with
identification, and the Notifications and Help rows in Profile arrive with
their features.

## Import

- The Add button opens the system photo picker, which needs no library
  permission. The app asks for the file as it is, so its metadata survives.
- `Services/PhotoMetadataReader.swift` reads the file with ImageIO on the
  device. It takes the camera settings, the capture time, and the location,
  and makes a copy of the image sized for the screen.
- Until identification exists, the user types the aircraft type, the
  registration, and the airline on the Add screen. None of them is required.
  A photo logged with no type is shown as "Unknown aircraft". It fills no
  type slot, and the types view lists it after the slots. "Edit aircraft
  details" on the photo screen names it later.
- A photo's saved location is kept with the photo. The spot map milestone
  shows disclosed photos to other people.
- The wording for camera settings, such as "1/640 s" and "f/7.1", lives in the
  core package so it is tested on Linux.

## Local collection

- A logged photo is saved on the device. `Services/PhotoStore.swift` keeps
  the photos in one JSON file and each image as a JPEG, inside Application
  Support. The saved image is the copy made for the screen, which carries no
  metadata, so the file holds no location.
- The store sits behind a protocol. Previews and tests run with no store and
  keep everything in memory.
- Deleting a photo removes its image file. Deleting the account removes every
  file. A sample photo the user deletes stays deleted, because its id is
  saved in a short list.
- A collection that cannot be read is left on the device as it is. The app
  says so and saves nothing that session, so the file is never written over.
- The collection has four views. Types, Airlines, and Registrations show one
  tile for each slot, and All photos shows one for each photo. A slot keeps
  the best shot, and a later shot takes it only with a strictly higher
  grade. A graded shot always beats an ungraded one.
- The slots are worked out from the photos each time by `CollectionBook` in
  the core package. Nothing about a slot is saved, so a deleted photo leaves
  no stale slot. Names that differ only in case or spacing share a slot.
- A blocked registration names no slot. A photo with no airline or no
  registration fills no slot in that view.
- A slot does not show a rarity yet. Rarity needs airframe counts and flight
  history, which arrive with identification and the backend.
- A logged photo with a location is linked to the nearest listed spot within
  1,500 meters, a placeholder in `SampleData`. The owner's located photos
  appear on the Spots map as small photo pins, shared or not, because only
  the owner sees that map. "Your photos" in the airport menu frames them all.
- Images are read from the device the first time each is shown and are not
  resized for the grid yet. A collection of many photos will want thumbnails.

## Technical check

- A picked photo is measured on the device before the Add screen opens.
  `Services/PhotoAnalyzer.swift` does it away from the main thread. Vision's
  foreground mask marks the aircraft's own pixels, and a formation comes back
  as one mask. When there is no mask, a box around the most prominent object
  stands in for it.
- Sharpness is the variance of the Laplacian over the aircraft's pixels.
  Exposure is the share of those pixels that is blown out or crushed.
  Framing uses the rectangle around the mask.
- A matte or dark aircraft has little detail to measure, so its sharpness
  reads low even in focus. Sharpness is therefore also divided by the
  variance of the aircraft's brightness, and the score is the better of the
  two readings.
- The scoring and the wording live in the core package, in `CheckRules` and
  `TechnicalCheckEngine`, so they are tested on Linux. Each measurement is
  scored by a curve of points, and the curves are data.
- Three checks run now, which are sharpness, exposure, and framing. A check
  that did not run is named as not checked on the technical check screen.
  - **Level horizon is built but turned off in the rules.** On 40 real
    photos Vision reported a tilt three times, each on an aircraft against
    open sky where it followed the wings, and never on the four photos with
    a real ground line. It needs another method before it is turned on.
  - Noise and heat haze are not built yet.
  - Every check needs the aircraft to be found. Detail over a whole photo
    did not tell sharp photos from soft ones, and blown pixels there are as
    likely to be clouds. A photo with no aircraft found is not scored, and
    its page says so.
  - Soft feedback reads the shutter speed. At the fast shutter time in the
    rules or faster it points to focus, haze, or a heavy crop, and not to
    the shutter.
  - Framing needs the mask. A box alone misses wingtips, rotors, and the
    rest of a formation.
  - An aircraft that fills most of the photo is treated as a deliberate
    close-up, so reaching a side is not held against it.
- A check has nothing to suggest when its score reaches the passing score.
  That never keeps a photo back, because the check is advice. See Grading
  below.
- A fix is worth the points the technical reading would gain if that check
  reached the fix target score. It is not worth points of the grade, which
  the votes alone set.
- The rules in `SampleData` are provisional. They come from 40 finished
  photos measured on a Mac on 2026-11-23. That set holds no rejects, so the
  low end of each curve is a guess, and the photos were edited web exports
  and not camera originals. Tuning needs soft, blurred, hazy, and badly
  exposed photos next.
- The iOS simulator cannot run the Vision requests that find the aircraft,
  and asking for the processor does not help. A photo imported there is not
  scored. The requests run on a Mac. Results on a real iPhone have not been
  checked yet.

## Grading

The owner decided on 2026-11-24 that the technical check coaches and the
votes decide. A photo that breaks the rules on purpose, such as a slow
shutter pan or a silhouette, must never be scored lower for it.

- The check runs before a photo is posted and lists what could be better.
  The photo can always be posted anyway.
- The result of the check is private to the photographer. No other user
  sees it.
- Every posted photo enters voting. Nothing about the check keeps one out.
- The public grade and the tier come from the votes alone. The 30 percent
  share that the design first gave to an AI score is dropped.
- Until a photo has enough votes, the photographer's own collection shows
  the technical reading as a private, provisional number, so the collection
  and its slots work for a photo nobody has voted on yet. Once the votes are
  in, they replace it.
- With no gate, a photo of nothing can reach the voting queue. A narrow
  filter for a photo with no aircraft found is the planned answer, and it
  is not decided yet.

What the app does now, and what is still to come in milestone 8.

- The photo screen and the technical check screen word the check as advice,
  and name its number a technical reading that only the photographer sees.
- `FinalGrade` in the core package is the vote score alone. `GradeWeights`
  is gone.
- A fix is worth points of the technical reading, and not of the grade.
- A photo with no grade shows its technical reading, dimmed and with no
  tier, on its tile in the owner's collection. A slot ranks ungraded shots
  by that reading, and a graded shot always outranks one.
- The photo screen posts a photo for votes. The button reads Post anyway
  when the check has ideas, and the check never stands in the way. A posted
  photo shows how many votes are in, and its grade once the votes set it.
  `docs/backend.md` has the details under Posting in the app.
- The Vote screen shows photos other people posted and takes a vote in
  stars. The voter picks stars and then casts the vote, because a vote
  cannot be changed. The screen shows the photo and nothing else.

## Identification

Identification runs in four steps, and the user only confirms the result.

1. **When and where.** Read the capture time, GPS position, and compass
   heading from the photo. When the position is missing, the user tags the
   location, with nearby spots and airports suggested first. A per-camera clock
   correction is remembered. A batch import is tagged once.
2. **What was flying there.** The backend asks the flight data provider for
   aircraft in a small box around that place and minute. Candidates are ranked
   by distance, altitude, and bearing, and the top three are shown.
3. **Reading the registration.** Apple Vision text recognition reads the
   registration off the fuselage on the device. A reading that matches a
   candidate confirms it. A reading with no flight data still identifies the
   aircraft through the public registry.
4. **Automatic description.** A confirmed match fills in registration, type,
   airline, flight number, route, and spot. The user can edit every field.

The flight data provider sits behind one interface with a sample data
implementation. The Flightradar24 API is the first candidate. Its historic
positions endpoint takes a timestamp and a bounding box. The light response
has position, callsign, and ICAO hex code only, and the full response, which
adds registration, type, airline, and route, needs a higher plan. The hex code
can be mapped to a registration through the public aircraft registry. The
provider key stays on the backend, and results are cached by place and minute.
The license terms for storing and showing results must be checked before
launch.

What runs on the phone today, with no backend:

- The text in a picked photo is read with Vision, and `RegistrationReader` in
  the core package finds a registration in it. Each country's format is data
  in `SampleData.registrationFormats`. A format written with a hyphen needs
  the hyphen, so a word such as DELTA is not read as the German D-ELTA.
- The Add screen offers the registration it read under Suggested, and a tap
  fills it in. It is not filled in by itself, because a wing or a winglet can
  hide the end of a registration and the part that shows still reads as a
  valid one. The user can change every field.
- A photo with no saved location can be placed with a pin on a map. The pin
  can go anywhere, with a search to move the map to an airport or a place by
  name, and the listed spots are marked on it. The pin places the photo on
  the Spots map, links it to a listed spot when one is within reach, and
  gives the flight lookup a place.
- `FlightRanker` ranks the aircraft near a photo by distance, height, and the
  direction the camera pointed, and keeps the best three. Its weights are
  placeholders in `SampleData.flightRankingRules`. A registration that matches
  a ranked flight confirms it and fills in the type, airline, flight, and
  route with no tap, since two sources agree.
- The app itself has no flight data yet. `SampleFlightDataProvider` is for
  previews and tests only, because a real photo matched against sample
  aircraft would be given the wrong identity.
- A registration on the block list is never suggested, and a photo logged
  with one keeps it hidden. The list is empty until the backend supplies it.

Still to come in this milestone: the public registry lookup for a reading
with no flight data, tagging a batch at once, and suggesting nearby airports
for a tag.

The flight data lookup, which is step 2 above, is built last. The owner
moved it there on 2026-11-24. It is milestone 10, after voting and the spot
map, and it brings the per-camera clock correction with it, since that only
matters when a photo's time is matched against flights. Until then a photo
is identified by the registration read from it and by what the user types.

## Backend

The backend is a CDK app in `backend/`. It has a table of records, a bucket
of images, a user pool that signs users in with Apple, and an HTTP API to
save, list, and delete the signed in user's own photos, to post a photo for
votes, to vote on other users' photos, and to delete the account. Posting,
the voting queue, casting a vote, and the grade are the backend's part of
milestone 8. The app's side follows them. The `beta` and `prod` stages are both deployed. A backend change
that reaches `main` goes to beta, and then to prod once the owner approves
the run. The app's side can sign in from the Profile screen, sync when the
app opens and after a change, and delete the account. A build made in Xcode
talks to beta, and a TestFlight build talks to prod. The design, the rules
for deleting and for syncing, and how to deploy are in `docs/backend.md`.

## Milestones

1. **Foundation.** Xcode project, core package, CI workflows, setup pages.
2. **UI pass.** Mockup review, then SwiftUI screens with sample data.
3. **Import and camera settings.** A library photo with full EXIF shows its
   camera settings on the photo detail screen.
4. **Technical check.** Sharpness, exposure, tilt, and framing run on the
   device and return feedback that names what to fix.
5. **Local collection.** Quickshot logging, slots, and upgrades, stored on the
   device. The user's own located photos appear on the Spots map, each linked
   to the nearest spot.
6. **Identification.** Location tagging, registration reading, and the
   automatic description. The flight data lookup is milestone 10.
7. **Backend foundation.** Sign in with Apple, photo upload, and sync in the
   beta account.
8. **Voting and final grades.** The technical check becomes advice before
   posting, and the votes alone set the grade. See Grading above.
9. **Spot map and spot pages.** Real spots from the backend, with the
   disclosed photos other people took there. An undisclosed photo never
   appears.
10. **Flight data lookup.** The backend asks the flight data provider what
    was flying near a photo, with the per-camera clock correction. It is
    last of the features because it needs a paid plan and a check of the
    provider's license terms.
11. **Launch preparation.** Release workflow, external TestFlight, App Store
    review. The prod account is already set up.
