# Releasing a new version to the App Store

Apple's first review of 1.0 (build 2, November 2026) stopped at Guideline 2.1, Information Needed. Apple wanted a screen recording from a physical device and written answers about the app. Do all of this before every submission, so the review doesn't stop there again.

## 1. Build and keep the archive

- Raise `CURRENT_PROJECT_VERSION` above the last upload, and raise `MARKETING_VERSION` for a new version.
- Archive to `~/Library/Developer/Xcode/Archives/`, not `/tmp`. A reboot clears `/tmp`, and the archive is the only way to put the exact reviewed build back on a phone. Build 2's archive is kept there as "Appellation Atlas 1.0 (2)".
- After the build, run `git checkout -- ios/AppellationAtlas.xcodeproj/project.pbxproj`. Never commit `ios/Config/Local.xcconfig`.

## 2. Test that exact build on real devices

- Install the archived app on the iPhone, with no rebuild:
  `xcrun devicectl device install app --device <UDID> "<archive>/Products/Applications/AppellationAtlas.app"`
- Go through the shot list below on the iPhone, and on an iPad if one is at hand. Apple reviews on physical devices.

## 3. Record the screen on the iPhone

- Update the iPhone to the latest iOS first (Settings › General › Software Update).
- Start on the home screen and tap the app icon, so the recording begins at launch.
- Shot list, about 2 minutes: turn and pinch the globe; France › Burgundy › Côte d'Or and scroll one page to its Sources; go back out; search a place; Save and Add notes, then show it on home; Where am I; About. Add whatever is new in the version, for 1.1: Compare, Often compared, Settings and Units.
- One iPhone recording is enough. Apple doesn't ask for one per device.
- Upload it under App Review Information › Attachment.

## 4. Write the App Review notes

Start from `build/appstore/review-notes.md` (the 1.0 notes, numbered the way Apple asked). Update before pasting into App Review Information › Notes, which holds 4,000 characters:

1. **Screen recording:** device, iOS version and build number.
2. **Purpose and audience:** the place count from the build (`public/places.json`).
3. **How to use it:** the steps must match the version's own screens. 1.1 changes the layout (Design D), so rewrite this from the new app, not the old notes.
4. **External services:** check again for anything new that reaches the network (`git grep -nE "URLSession|StoreKit|WebKit|import Network" -- ios`). Today it is iCloud, Core Location, WidgetKit and links that open in Safari.
5. **Regional differences:** none.
6. **Regulated and third-party material:** wine is information only, with no sales or prices, and rated 18+. List the data sources and their terms. **1.1 adds Compare text written from Wikipedia (CC BY-SA), Wine Folly and a few other sites, credited in each compare's Sources: say so.** Keep the WorldClim permission email ready, since the notes offer it on request.

Also say plainly: no login, no user content others can see, no purchases.

## 5. Store listing

- Retake the screenshots when the screens change (1.1 does). Guideline 2.3.3 wants the real app in use.
- Update the description's place count and features, and the What's New text.
- Keep the age rating (18+), the 128 countries and Data Not Collected unless something changed. If the app starts sending data anywhere, redo the privacy label.
