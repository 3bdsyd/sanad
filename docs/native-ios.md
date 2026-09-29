# iPhone integration

The iOS navigation bar is a real UIKit platform view, registered in
[AppDelegate.swift](../ios/Runner/AppDelegate.swift). Its implementation lives in
[FursaNativePlugin.swift](../ios/Runner/FursaNativePlugin.swift).

## Native navigation

Use [NativeNavigation](../lib/core/native_navigation.dart) **directly** as the
Scaffold's `bottomNavigationBar`, without a wrapping SafeArea or any external
padding. With `extendBody: true`, the content scrolls behind the system glass.
The native bar reports its fitted height, including the home-indicator area.
Logical indexes are `0` for opportunities, `1` for saved opportunities, and `2`
for posting/managing opportunities. There are exactly three real destinations;
opportunities appear on the right in RTL.

The iPhone implementation now embeds a **real `UITabBar`**, using the same
platform-view approach as the team's Surfa app. It does not draw a row of
UIButtons inside a visual-effect view. When linked with the iOS 26 SDK, iOS 26
supplies the actual Liquid Glass capsule, selection morph, press-and-slide
selection, system item colors and accessibility behavior. Earlier iOS releases
keep their native translucent tab-bar appearance. The selected tint is Sanad blue `#20508A`; unselected artwork is `#12233F`.
The three icons are original Sanad vector glyphs (home, heart and plus),
rendered by Core Graphics into 22-point template artwork. Their 24-unit paths,
1.7-point rounded strokes without decorative accent fills come from the same JSON source as
Flutter. [generate_ui_icons.py](../tools/generate_ui_icons.py) generates both
Dart geometry and [FursaIconCatalog.swift](../ios/Runner/FursaIconCatalog.swift),
which is registered in the Runner Sources build phase. UIKit still owns
labels, glass and selection, and cannot enlarge an SF Symbol configuration on
top of the explicit artwork. Three destinations
will naturally produce different item widths from a Surfa bar with more tabs.
No private UIKit APIs or manually painted native selection pill are used.

The Flutter `UiKitView` forwards touch gestures eagerly so the system handles
selection. Native selection reports back to Flutter; programmatic Flutter tab
changes also synchronize the system selection. UIKit owns Reduce Motion,
VoiceOver and selection feedback for the native tab bar.

The platform-view identifier is `app.fursa/navigation`. Each view uses its own
`app.fursa/navigation/<viewId>` method channel:

| Direction | Method | Argument/result |
| --- | --- | --- |
| Dart → UIKit | `setSelected` | Integer index, 0–2 |
| Dart → UIKit | `getHeight` | Returns the fitted system height |
| UIKit → Dart | `onSelected` | Integer index, 0–2 |
| UIKit → Dart | `onHeightChanged` | Fitted system height, including safe area |

The initial height query covers the case where native layout happens before
Dart's channel handler is registered. Further layout/safe-area changes send new
heights. Flutter does not impose the old fixed 76-pixel native bar height.

Web and Android use a Flutter `BackdropFilter` capsule, with a translucent
sliding selection, RTL press-and-slide, thin home/heart/plus icons and the same
three destinations. The fallback owns its horizontal inset and bottom safe
area. It respects Reduce Motion for app-authored animations, but its blur is an
approximation rather than Apple's Liquid Glass rendering.

## Symbols and haptics

[NativeBridge](../lib/core/native_bridge.dart) uses `app.fursa/native`:

- `symbol(name, size: 24, color: ...)` requests a transparent, 3× PNG of an SF
  Symbol. Dart caches the result. Missing symbols or unsupported platforms
  return `null`, so the caller can display a Flutter icon instead.
- `selectionHaptic()` uses `UISelectionFeedbackGenerator` on iOS and Flutter's
  selection feedback elsewhere. Haptics are optional and failures are ignored.

## Local persistence and privacy

[Runner.entitlements](../ios/Runner/Runner.entitlements) is attached to Debug,
Profile and Release. Its empty `keychain-access-groups` entry follows the
installed `flutter_secure_storage` setup for app-local Keychain storage. The
project does not share credentials with another application or use App Groups.
Management tokens remain in secure storage; cached opportunities and saved IDs
use app-local preferences. Keychain contents can survive app reinstalls; do not
promise that uninstalling is a secure deletion mechanism.

[PrivacyInfo.xcprivacy](../ios/Runner/PrivacyInfo.xcprivacy) is included in Runner's
resources. It declares app-only UserDefaults access with reason `CA92.1` and no
tracking. Live mode accepts employer names, email addresses, phone numbers and
job/report content for app functionality, so those data types are declared.
Demo mode stays local. This file must remain aligned with the actual deployed
backend, any later SDK additions, the privacy policy and App Store Connect's
privacy answers. It is not a substitute for those publishing details.

Contact buttons call `launchUrl` directly and handle failure in the app. There
is no `canLaunchUrl` query, so no `LSApplicationQueriesSchemes` list is needed.
No contacts, phone-call, photo-library or location permission is requested.
The chosen city is a filter, not GPS access. iOS Simulator may lack a phone or
email handler; verify these contact actions on an iPhone with the relevant apps.

## Branding and signing

The app display name is **سند**. The native launch storyboard and first Flutter
frame share the `#F2F7FC` screen canvas and a **96 × 96-point** high-contrast
logo tile centered in the complete window. The tile uses `#20508A`, a pale
mark, and a **24-point** corner radius, so it no longer disappears into the
launch background. The main Flutter host view keeps the screen canvas to avoid
a white frame during startup. The native launch is static; Flutter continues
with the matching high-contrast brand animation after its first frame. The
approved source silhouette remains [sanad-logo.png](../assets/images/sanad-logo.png),
and the generated startup variant is
[sanad-logo-contrast.png](../assets/images/sanad-logo-contrast.png).
The iOS catalog also includes an explicit luminosity-dark 1024px rendition in
pure white on black. That wider luminance range stays legible after iOS applies
its dark icon treatment instead of collapsing the two brand blues together.
The tinted slot remains system-generated because iOS owns the user's selected
tint treatment.

Android before API 31 uses the same centered 96dp high-contrast tile. Android
12+ receives a 288dp transparent splash drawable with the 96dp tile centered
inside the system safe circle. Both light and dark launch themes use the app’s
light screen canvas around the deep tile.
Adaptive Android launcher icons preserve artwork within the safe zone.
Web has the same 96px logo until the Flutter engine emits `flutter-first-frame`.

Regenerate iOS, Android and web assets from the approved master with
[generate_brand_assets.py](../tools/generate_brand_assets.py):

```sh
python3 tools/generate_brand_assets.py
```

The script requires Pillow on the development machine, not at app runtime. iOS
icons are opaque RGB PNGs; iOS applies its own icon mask. Do not add baked-in
round corners to the iOS asset catalog.

The generated personal `DEVELOPMENT_TEAM` was removed. To install a signed
iPhone build or publish, open `ios/Runner.xcworkspace`, choose the actual team's
signing identity and a registered bundle ID, then build with the production API:

```sh
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://YOUR_API_HOST \
  --dart-define=SUPPORT_URL=https://YOUR_SITE/support \
  --dart-define=PRIVACY_URL=https://YOUR_SITE/privacy
```

The hostnames above are placeholders. Live release builds require all three
HTTPS URLs. Never distribute a production build with an empty `API_BASE_URL`,
which intentionally enables local demo mode.

## Verification

The reference redesign was rebuilt with `flutter build ios --simulator --debug`
after the welcome decorative-layer hit-testing fix. The later original-icon
revision was also rebuilt; final verification is listed below. The Swift bridge also passed
an arm64 iOS Simulator type-check against the installed iOS 26.5 SDK and Flutter
framework; the native-navigation Dart file passed analysis.

A temporary XCTest UI runner outside the repository verified the actual UIKit
bar on an isolated iPhone 17 / iOS 26.5 simulator named **Fursa Reference Preview**
(`2C07C081-9785-4835-BEC1-B3156A7F7BE9`). It found exactly three UITabBar buttons
and tapped Saved, Add Opportunity and Opportunities, asserting the selected
state after every tap. The final native-tab check passed. The original-vector revision passed a second
scoped run after its final rebuild: each native tap also revealed the expected
Flutter Saved/Publishing heading. Final screenshots use the 22-point original
artwork, not the earlier oversized SF Symbol configuration. The measured bar was
83 points high including the safe area, with UIKit's 62-point inner capsule;
RTL order put Opportunities on the right. No test target or new automated-test
workflow was added to this app. Existing user simulators were left untouched.

- [Welcome on iPhone](screenshots/reference-iphone-welcome.png)
- [Opportunities and the system bar](screenshots/reference-iphone-home.png)
- [Saved tab selected](screenshots/reference-iphone-saved.png)
- [Publishing tab selected](screenshots/reference-iphone-publish.png)

The first UI passes exposed a decorative painter intercepting the Skip button,
which was corrected with IgnorePointer, and a simulator keyboard tutorial
obscuring the bar. The successful final tab run followed those findings. Native
scrub/press feel, VoiceOver, Reduced Motion, older iOS and physical hardware were
not separately exercised and are not claimed by that tap check.

After native navigation changes, type-check the Swift bridge and build the
actual simulator app. Dart analysis alone cannot validate the UIKit integration.
The Sanad change keeps the existing AppDelegate plugin registration and adds
the generated `FursaIconCatalog.swift` to Runner Sources. Technical `app.fursa.*`
identifiers and storage namespaces remain stable so rebranding does not lose
saved jobs or announcement management credentials.

The Sanad revision passes Interface Builder launch-storyboard compilation,
Swift type-check of the generated catalog and UIKit plugin against iOS 26.5,
plist/project lint, XML parsing of Android resources, and an asset audit of
19 opaque iOS app icons, three matched launch scales, 15 Android splash/adaptive
images, five legacy Android launcher sizes, and four web manifest icons. These structural
checks do not replace the final whole-app simulator build or Android device
verification; see the current brand documentation for the complete run record.

Useful development commands:

```sh
flutter analyze
flutter build ios --simulator --debug
flutter run -d YOUR_SIMULATOR_ID
```

Check all three native tab touch targets and the RTL logical mapping, selection
sync after opening/dismissing a page, the safe-area placement in portrait and
landscape, the system scrub gesture, and content scrolling behind glass. Compare
against Surfa on the same iOS release; Apple controls the system appearance, so
older iOS releases do not reproduce iOS 26 Liquid Glass exactly.

Physical-device installation/signing, haptic feel, VoiceOver and direct phone/
email handoff require their own checks. A screenshot does not establish those
behaviors. Historical native screenshots from the initial custom-button bar
are not evidence for the replacement UITabBar.

## References

- [Apple: launching](https://developer.apple.com/design/human-interface-guidelines/launching)
- [Android: splash-screen icon dimensions](https://developer.android.com/develop/ui/views/launch/splash-screen)
- [Flutter: web initialization](https://docs.flutter.dev/platform-integration/web/initialization)
- [Flutter: hosting native iOS platform views](https://docs.flutter.dev/platform-integration/ios/platform-views)
- [Apple: system tab bar](https://developer.apple.com/documentation/uikit/uitabbar)
- [Flutter Secure Storage setup](https://pub.dev/packages/flutter_secure_storage)
- [URL Launcher platform configuration](https://pub.dev/packages/url_launcher)
- [Apple: privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple: collected data types](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)
