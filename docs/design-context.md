# Plane Photography App, Design Context

## About This Document

This document is the full context for designing and building a plane spotting photography app. It is written to be handed to Claude Code as the basis for a high-level design. It stands on its own and does not depend on any other document.

Sections marked **Decided** are settled. Sections marked **Proposed** are reasonable defaults that can change during design. **Open Questions** at the end need answers before or during design.

## 1. Product Summary

A mobile app where plane spotters photograph real aircraft to build a collection of types, airlines, liveries, and individual airframes, and where better photos are worth more. Every shot gets specific feedback on what to fix before it is posted, and its grade comes from community votes. Higher grades earn higher tiers in the collection, XP, and a chance to be featured on a map of spotting locations.

Identification is handled largely by matching the photo's time and location against ADS-B flight data, so logging is fast and accurate. Rare arrival alerts give users a reason to go out and shoot.

The founder is a real-world photographer and the app is built around rewarding photography skill, inspired by the photo collection loop in Forza Horizon 6.

## 2. Problem and Context

Plane spotting is split into two camps with nothing in between.

- **Curated databases** like JetPhotos, Airliners.net, and Planespotters.net have high standards but slow, opaque screening. Spotters have long complained about arbitrary rejections and long queues.
- **Collection and social apps** already exist. Sky Cards (from the Flightradar24 team) gives cards for catching nearby flights, but the photo is simulated. PlaneSpot, SpotAir, and WhatPlane identify aircraft from real photos and add them to a hangar. Airside uses rarity tiers based on production numbers. FlightSpot ranks nearby aircraft by rarity using ADS-B. AeroNatics and Aviatter are social feeds with map pins.

None of these grade the photo itself. A blurry phone shot of a 737 counts the same as a sharp, well-composed one. None explain why a shot would be rejected by the big databases.

## 3. Main Differentiator (Decided)

**The app rewards taking better pictures.** Every shot gets specific, fixable feedback from an AI technical check before it is posted, and a grade from community votes. The check coaches and never marks a photo down, so a shot that breaks the rules on purpose is not penalized for it. Better shots unlock higher collection tiers. The collection mechanic alone is not novel for planes, so grading and feedback must drive design priorities.

## 4. Target Users

| User | What they want |
|---|---|
| Aviation photographers | Recognition for skill, feedback that helps them pass screening on the big databases |
| Plane spotters | A collection to fill down to the registration level, rarity to chase, alerts for interesting arrivals |
| Casual aviation fans | An easy way to identify and collect what they see |

## 5. Core Loop

1. User photographs an aircraft in the app or uploads from their camera roll
2. App matches the photo's timestamp and GPS against ADS-B history to identify the aircraft
3. User confirms the registration, type, and airline
4. The photo is logged as a Quickshot, filling any new collection slots
5. User can submit the shot for grading
6. AI technical check runs instantly and returns feedback, before the shot is posted
7. The user can fix the shot or post it anyway, and a posted shot enters community voting
8. The votes set the final grade, which sets the tier for that collection slot
9. A later, better shot of the same aircraft can upgrade the slot

## 6. Scope

### MVP (Decided)

- Account creation and profile
- Camera capture and camera roll upload
- ADS-B matching identification with manual fallback
- Collection catalog for types, airlines, and registrations
- Quickshot logging
- Graded shot flow with AI technical check and feedback
- Community voting queue
- Tier assignment and slot upgrades
- Spotting locations map
- Undisclosed location option on posts

### Later

- Rare arrival alerts
- Active runway highlighting from live wind data
- Special livery collection
- Weekly photo challenges
- Registration OCR as a second identification check
- Screening likelihood check for the major databases
- Custom aesthetic model trained on community votes
- Following other users and a social feed
- Android client if MVP is iOS only

### Non-Goals

- Full live flight tracking map competing with Flightradar24
- Flight logging for trips the user has taken
- Any use of Forza branding, names, logos, or game assets

## 7. Functional Requirements

### FR-1 Capture and Upload

- User can take a photo in-app or pick one from their library
- EXIF data (camera, lens, focal length, aperture, shutter speed, ISO, timestamp, GPS) is read and stored when present
- Photos without timestamp or GPS fall back to manual identification

**Acceptance** A library photo with full EXIF shows its camera settings on the photo detail screen.

### FR-2 Identification

- Using the photo's timestamp and GPS, query ADS-B history for aircraft within a set radius and time window
- Rank candidates by distance, altitude, and heading relative to the camera
- Show the top candidates with registration, type, and airline for the user to confirm
- If no match is found (common for military aircraft), user can search by registration or enter it manually

**Acceptance** A photo of a landing airliner taken near a busy airport returns the correct registration as the top candidate in most cases.

### FR-3 Collection

- Collection has four views, aircraft types, airlines, registrations, and liveries (liveries in Later)
- One photo can fill slots in several views at once
- Each slot keeps the user's best shot and can be upgraded by a better one
- Each slot shows a rarity tier

**Acceptance** Logging a new registration of an already-collected type fills the registration slot without changing the type slot unless the new shot grades higher.

### FR-4 Grading

See Section 8 for the full design.

- Grading is opt-in per photo
- AI technical check returns specific feedback within a few seconds, before the photo is posted
- The feedback is advice, shown only to the photographer, and the photo can be posted anyway
- Every posted shot enters community voting
- Grade finalizes after the voting window closes and minimum votes are met

**Acceptance** A tilted shot with heat haze gets feedback naming both problems, and can still be posted and voted on.

### FR-5 Community Voting

- Voters see photos one at a time without the photographer's name or current score
- Votes are whole stars from 1 to 5 (decided on 2026-11-24)
- Users cannot vote on their own photos
- Vote weight depends on voter reputation

**Acceptance** A user's own photos never appear in their voting queue.

### FR-6 Spotting Map

- Map shows spotting locations with a name, pin, description, access notes, local photography rules, and best time of day per runway direction
- Graded shots taken at a spot appear on its page, best first
- Posts can use an undisclosed location, which hides the pin entirely

**Acceptance** A post marked undisclosed shows no location to any other user.

### FR-7 Rewards

- Tiers per slot (proposed Logged, Bronze, Silver, Gold)
- XP for new slots, graded shots, and upgrades
- Top-graded shots featured on spot pages

### FR-8 Rare Arrival Alerts (Later)

- User picks home airports and alert preferences
- Alerts fire for rare types, special liveries, diversions, or first visits by an airline
- Built on the same ADS-B source as identification

## 8. Grading System Design

### Layer 1, Technical Check (Decided Approach)

Runs on-device where possible so feedback is instant. Uses standard computer vision, no custom model required to start. These checks map to the most common rejection reasons on the big databases.

| Check | Method | Example feedback |
|---|---|---|
| Sharpness | Variance of the Laplacian inside the aircraft's bounding box | "The aircraft is soft, try a faster shutter speed" |
| Tilt | Line detection on horizon, runway edges, or fuselage | "Horizon is tilted about 2 degrees" |
| Exposure | Histogram analysis for clipped highlights and crushed shadows | "White fuselage is overexposed" |
| Noise | Standard noise estimation | "Heavy noise, try lower ISO" |
| Heat haze | Local distortion detection around the aircraft edges | "Heat haze is softening the image, shoot earlier in the day or closer" |
| Framing | Object detection for aircraft size, position, and cutoff | "Tail is clipped, zoom out slightly" |

All thresholds should live in config so they can be tuned without a release.

The technical check is a coach and not a gate. The owner decided this on 2026-11-24, so that a photo is never scored lower for creativity. The check runs before a photo is posted and says what could be better. Only the photographer sees its result, and the photo can be posted anyway. It takes no part in the public grade. Until a photo has enough votes, the photographer's own collection shows the technical reading as a private, provisional number.

### Layer 2, Aesthetic Score (Proposed)

- Start with a pretrained aesthetic model such as NIMA or a CLIP-based aesthetic predictor
- These are not tuned for aviation photography and will be rough at first
- A vision language model can turn scores and checks into readable feedback
- Do not train on scraped photos from JetPhotos, Airliners.net, or other sites

### Layer 3, Community Votes (Decided)

- Covers what the AI can't judge well at launch, like composition, light, and mood
- Voting window of 72 hours with a minimum of 5 votes, both tunable. A photo short of votes at the end of its window stays open until it has them
- Blind voting with scores hidden until close
- Votes weighted by voter reputation, which grows when a voter's ratings align with final grades

### Final Grade (Decided on 2026-11-24)

- Final score is the weighted vote average, on a 0 to 100 scale
- The technical check and any AI score take no part in it, so no photo is marked down for style
- The earlier proposal blended 30 percent AI with 70 percent votes, and it was dropped
- Every grade shows the reasons behind it so it never feels arbitrary

## 9. Identification Design (Proposed)

- Primary method is ADS-B history matching using photo timestamp and GPS
- Search window of roughly 60 seconds and a few kilometers around the camera, tunable in config
- Candidates scored by distance, altitude, and bearing from the camera
- Registration OCR on the fuselage is a Later addition for cross-checking
- Manual entry by registration as a fallback
- Aircraft metadata (type, operator, age) from a public registry such as the OpenSky aircraft database or the FAA registry

## 10. Rarity (Proposed)

- Type rarity seeded from how many airframes of that type are still active
- Registration rarity based on how often the airframe visits the user's region, using ADS-B history
- Boosts for retiring fleets and special liveries
- Proposed tiers are Common, Uncommon, Rare, Epic, Legendary

## 11. Data Model (Proposed)

| Entity | Key fields |
|---|---|
| User | id, display name, avatar, XP, reputation score, home airports, created at |
| Photo | id, user id, storage key, EXIF fields, captured at, location, undisclosed flag, spot id (optional) |
| Identification | photo id, ADS-B candidates with scores, confirmed registration, method |
| Aircraft | registration, ICAO hex, type code, operator, first flight date, active flag |
| AircraftType | type code, manufacturer, model, active airframe count, rarity tier |
| Airline | ICAO code, name, country |
| CollectionEntry | user id, slot kind (type, airline, registration, livery), slot key, best photo id, tier, first logged at, upgraded at |
| TechnicalCheck | photo id, pass flag, per-check scores, feedback messages |
| Grade | photo id, AI aesthetic score, vote score, final score, tier, status, finalized at |
| Vote | photo id, voter id, value, voter weight at time of vote, created at |
| Spot | id, name, lat and long, airport code, runway notes, access notes, local rules |

## 12. Architecture and Stack (Proposed)

Defaults chosen to match the founder's experience with SwiftUI and AWS. Any of these can change during design.

| Layer | Proposed choice |
|---|---|
| Client | iOS app in SwiftUI |
| On-device vision | Apple Vision and Core ML for sharpness, tilt, exposure, and framing checks |
| Auth | Amazon Cognito with Sign in with Apple |
| API | API Gateway with Lambda |
| Database | DynamoDB |
| Photo storage | S3 with CloudFront |
| ADS-B history | External provider, see Section 13 |
| Feedback text | Hosted vision model through Amazon Bedrock |
| Maps | MapKit |
| Sun position | Computed client-side from spot coordinates, runway heading, and date |

## 13. External Dependencies

| Need | Options | Notes |
|---|---|---|
| ADS-B history | OpenSky Network, ADS-B Exchange, FlightAware AeroAPI, Flightradar24 API | OpenSky is free for research and non-commercial use. Others are paid. Licensing must be checked before launch. |
| Aircraft registry | OpenSky aircraft database, FAA registry download | Public data, refresh periodically |
| Weather and wind | Public METAR feeds | Needed for active runway highlighting in Later |

## 14. Privacy, Safety, and Legal Constraints (Decided)

- Respect blocked registrations, including aircraft enrolled in programs like the FAA's LADD list, by hiding their identity in the app
- Support undisclosed locations for sensitive or military sightings
- Spot listings note local airport photography rules and never encourage entering restricted areas
- Users can delete photos and their account, and deletion removes stored images
- No Forza name, logos, UI, or assets anywhere in the app or marketing
- No scraping of other photo sites for training data
- Follow the license terms of whichever ADS-B provider is used

## 15. Open Questions

- iOS only for MVP, or cross-platform from the start?
- Which ADS-B provider, and what does it cost at expected volume?
- How accurate is ADS-B matching for distant or high-altitude aircraft?
- Should spots be user-created from day one or curated at launch?
- How should reputation be bootstrapped for early voters?
- Will the grading engine later be shared with a car photography version, and should the architecture plan for that now?

## 16. Glossary

| Term | Meaning |
|---|---|
| ADS-B | Broadcast signal most aircraft send with their position and identity |
| Registration | An aircraft's unique tail number, such as N12345 |
| Quickshot | Any photo that logs an aircraft to the collection without grading |
| Graded shot | A photo submitted for AI check and community voting |
| Slot | A single entry in the collection, by type, airline, registration, or livery |
| Tier | The grade level of a slot's best photo |
| Spot | A pinned spotting location on the map |
| Screening | The approval process used by JetPhotos, Airliners.net, and Planespotters.net |

## 17. References

- [Sky Cards review on EFTM](https://eftm.com/2024/12/sky-cards-is-the-ultimate-plane-spotter-game-for-apple-and-android-phones-258057)
- [PlaneSpot on the App Store](https://apps.apple.com/ca/app/plane-identifier-ai-planespot/id6736696480)
- [SpotAir](https://appshunter.io/ios/app/spotair-plane-spotting-ai/id6743351021)
- [Airside on the App Store](https://apps.apple.com/app/id6760658695)
- [FlightSpot](https://mwm.ai/apps/flightspot-plane-radar/6789645301)
- [AeroNatics on the App Store](https://apps.apple.com/app/aeronatics/id6755212824)
- [Aviatter on the App Store](https://apps.apple.com/app/aviatter/id1595625341)
- [FlightAware forum thread on photo site screening](https://discussions.flightaware.com/t/uploading-to-photo-sites-no-stupid-reasons-to-reject-a-pic/5257)
