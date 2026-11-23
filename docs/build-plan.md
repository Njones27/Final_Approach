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
| Spots | Curated at launch |
| Reuse | Grading logic lives in `Packages/FinalApproachCore` so a car photography version could share it |
| Order of work | UI design first, then one small milestone at a time |
| Look | Darkroom. A true black ground in dark mode and white in light mode, photos first, one condensed face for numbers. See the next section |
| Appearance | Follows the iPhone setting, with a System, Light, or Dark choice in Profile |

## Interface

The look is called Darkroom. The rules below apply to every screen.

- Four tabs hold the four sections, which are Collection, Spots, Vote, and
  Profile. Adding a photo is an action, so it is a button on Collection and
  not a tab. The tab bar hides on pushed screens.
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
- The tier thresholds of 50, 65, and 80, the passing score of 75 for one
  check, and the points for each fix are placeholders in `SampleData`. They
  are passed in as data and are not decided yet.

Two controls from the mockups wait for the milestone that gives them something
to do. "Pick a different aircraft" on the Add screen arrives with
identification, and the Notifications and Help rows in Profile arrive with
their features.

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

## Milestones

1. **Foundation.** Xcode project, core package, CI workflows, setup pages.
2. **UI pass.** Mockup review, then SwiftUI screens with sample data.
3. **Import and camera settings.** A library photo with full EXIF shows its
   camera settings on the photo detail screen.
4. **Technical check.** Sharpness, exposure, tilt, and framing run on the
   device and return feedback that names what to fix.
5. **Local collection.** Quickshot logging, slots, and upgrades, stored on the
   device.
6. **Identification.** Location tagging, registration reading, the flight data
   lookup, and the automatic description.
7. **Backend foundation.** Sign in with Apple, photo upload, and sync in the
   beta account.
8. **Voting and final grades.**
9. **Spot map and spot pages.**
10. **Launch preparation.** Prod account, Release workflow, external
    TestFlight, App Store review.
