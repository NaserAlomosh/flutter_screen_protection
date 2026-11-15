# flutter_screen_protection

Android-only Flutter screenshot protection using `WindowManager.LayoutParams.FLAG_SECURE`.
Exactly two policies: a global backend-supplied Boolean and a configurable set of protected route names. Android minimum API 29; validation targets API 29–37. See [verification](docs/VERIFICATION.md) for executed results, not a blanket device compatibility claim.

## Initialize before showing content

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterScreenProtection.initialize(
    screenshotsEnabled: false,
    protectedRoutes: ['/login', '/account-details', '/transfer', '/card-details'],
  );
  runApp(MaterialApp(
    navigatorObservers: [FlutterScreenProtection.navigatorObserver],
    initialRoute: '/home',
    routes: {/* your named routes */},
  ));
}
```

Both native and Dart state start blocked. Until the observer knows a named route, protection remains on. `initialize` may be repeated to replace both configurations; it does not reset navigation. The plugin does not fetch backend configuration or persist it across process death.

For protection **before plugin attachment**, add this to your Android FlutterActivity. It also protects the native launch window. Use a non-sensitive launch theme/splash:

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    super.onCreate(savedInstanceState)
}
```

The plugin owns this window flag. Do not independently clear it, and do not attach multiple policy engines to the same Activity. Other Activities/windows require their own protection.

## Update the two policies

```dart
await FlutterScreenProtection.setScreenshotsEnabled(response.screenshotsEnabled);
await FlutterScreenProtection.setProtectedRoutes(['/account-details', '/transfer']);
```

`false` blocks the whole window. `true` permits screenshots only when the visible route is known and unprotected. Route names are exact, case-sensitive matches; there is no prefix or wildcard matching. Unnamed routes (including unnamed dialogs), an empty navigator, and initialization are blocked. Nonopaque overlays cannot uncover a protected underlying route. Outgoing protected routes stay protected until their transition overlays have been removed. Runtime list updates also reevaluate outgoing routes.

| Global enabled | Route | Result |
|---|---|---|
| false | any | Blocked |
| true | `/home` (unprotected) | Allowed |
| true | `/transfer` (protected) | Blocked |
| true | unnamed / unknown | Blocked |

All setters return a Future that acknowledges native application (or storage while an Activity is temporarily detached). Await it before presenting newly sensitive content. Failures propagate as platform errors. Observer-triggered errors are reported via `FlutterError.reportError`; treat those as a protection failure, not permission to display sensitive data.

## Navigation and first-frame protection

Register the singleton observer **once on one root Navigator**, before its initial route. Standard named push, pop, replacement, removal, back navigation and restored routes are tracked. Names must be supplied in `RouteSettings` for manually constructed routes.

An observer callback is synchronous; a platform-channel window update is asynchronous. Observer registration alone cannot guarantee that Android has acknowledged protection before the first frame of a newly pushed sensitive route. For that guarantee, wrap navigation from an allowed screen:

```dart
await FlutterScreenProtection.protectNavigation(() {
  Navigator.of(context).pushNamed('/transfer');
});
```

The guard waits for native blocking before invoking the synchronous navigation callback, and holds protection through the next frame. Do not make that callback async or await the Navigator's returned pop future. Use the guard for deep links, replacements, route-list additions before revealing sensitive content, and programmatic changes that introduce sensitive UI. The example uses it for every push. If callers cannot guard navigation, keep global screenshots disabled. For a system-back gesture that reveals a protected route underneath an allowed route, intercept back navigation in the application (for example with PopScope) and use the guard, or keep global protection enabled. An observer alone cannot synchronously block that first reveal frame. Already-protected screens remain secure during pops; outgoing transition tracking prevents early clearing.

For Navigator 2.0 use stable `Page(key: ValueKey('/transfer'), name: '/transfer', ...)` identifiers and install the observer on that Navigator. For `go_router`, provide `MaterialPage(key: ValueKey('/transfer'), name: '/transfer', child: ...)` from `pageBuilder` and attach the observer through the router's observer configuration. Change the Page key when its policy identity changes; mutating only a name on the same route is not a navigation notification. Guard `router.go(...)` before changing pages. Do not assume URL paths or GoRoute names are automatically exposed as `RouteSettings.name`. Nested Navigators / ShellRoute branches are not automatically aggregated: supply navigation through a single observed root with stable names, or keep global protection enabled. This package does not discover nested navigation state.

## Lifecycle and platform limits

Kotlin applies window operations on the main thread. Ordered channel messages carry the complete effective Boolean, so backend and route updates cannot independently clear each other's restrictions. The latest policy is retained across temporary Activity detach/reattach for the same Flutter engine. Engine disposal leaves the last window secure and releases Activity references. A new engine or process starts blocked; restore backend policy explicitly after startup. Flutter's route restoration must provide stable route names.

`FLAG_SECURE` prevents the window from appearing in screenshots and non-secure displays; capture paths can refuse capture or return blank content. It is whole-window protection, not screenshot detection or selective masking. It is not protection against cameras, compromised/rooted systems, or every OEM bug. ADB screencap and System UI screenshots are separate validation paths.

- [Android FLAG_SECURE documentation](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_SECURE)
- [Flutter NavigatorObserver documentation](https://api.flutter.dev/flutter/widgets/NavigatorObserver-class.html)
- [Example](example/lib/main.dart)
- [Validation report](docs/VERIFICATION.md)

This is a breaking rebuild. All old capture events, monitoring, selective-content APIs and iOS support have been removed. Historical research in `docs/archive` is not current functionality.
