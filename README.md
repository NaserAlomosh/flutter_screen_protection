# flutter_screen_protection

Android-only screenshot protection with two policies: a backend-supplied global Boolean and a list of protected Flutter route names. Uses Android `FLAG_SECURE`; minimum API 29. See [automatic navigation verification](docs/AUTOMATIC_ROUTE_PROTECTION.md) for API 29–37 execution results and limitations.

## Configure once at the root

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterScreenProtection.initialize(
    screenshotsEnabled: true, // Supply the backend value; default is false.
    protectedRoutes: ['/login', '/transfer', '/account-details', '/card-details'],
  );
  runApp(MaterialApp(
    builder: FlutterScreenProtection.builder,
    navigatorObservers: [FlutterScreenProtection.navigatorObserver],
    initialRoute: '/home',
    routes: existingRoutes, // Keep your existing routes or onGenerateRoute factory.
  ));
}
```

**Both the builder and observer are required for automatic first-frame protection.** Register the singleton observer on one root Navigator. The builder must enclose that Navigator and all sensitive Flutter UI. If you already have a MaterialApp builder, compose it centrally:

```dart
builder: (context, child) => FlutterScreenProtection.builder(
  context,
  existingBuilder(context, child),
),
```

Screens and existing navigation calls stay unchanged:

```dart
Navigator.pushNamed(context, '/transfer');
Navigator.pop(context);
Navigator.pushReplacementNamed(context, '/login');
```

No per-screen wrapper, route subclass, replacement navigation API, or `protectNavigation` call is required. The same builder can wrap a standalone Navigator through a root `Builder` widget; attach `navigatorObserver` to that Navigator's `observers` list.

## Public API

- `initialize({bool screenshotsEnabled = false, List<String> protectedRoutes = const []}) → Future<void>`
- `setScreenshotsEnabled(bool enabled) → Future<void>`
- `setProtectedRoutes(List<String> routes) → Future<void>`
- `builder(BuildContext context, Widget? child) → Widget`
- `navigatorObserver → NavigatorObserver`
- `protectNavigation(VoidCallback navigate) → Future<void>` remains an optional legacy helper. The root integration does not need it; existing callers can migrate without changing their screens.

```dart
await FlutterScreenProtection.setScreenshotsEnabled(response.screenshotsEnabled);
await FlutterScreenProtection.setProtectedRoutes(['/account-details', '/transfer']);
```

The plugin does not fetch or persist backend configuration. `false` always blocks, even on an unprotected route. Names match exactly and case-sensitively. Unknown/empty names, an empty Navigator and startup fail closed. Nonopaque routes cannot uncover protected content underneath them. Copying the supplied list prevents later caller mutations from silently changing policy.

## How automatic rendering protection works

The observer updates policy synchronously when routes or gestures change. The root builder installs a render boundary around the Navigator:

1. Before protected pixels can enter the displayed scene, the gate checks whether Android has acknowledged a secure window. If not, it paints a neutral black frame and excludes the Navigator's layers, pointer hit testing and subtree semantics.
2. Protected widgets can still build, lay out, or update offscreen cached layers; their Flutter pixels are not added to the displayed scene while the gate is closed. This also covers cached route layers revealed by pop.
3. The native method reply opens the gate only if it belongs to the latest policy request. An old acknowledgement cannot open a newer protected navigation after an intervening allowance request.
4. Protection remains active while protected outgoing routes or interactive back gestures can reveal sensitive content.
5. Before clearing `FLAG_SECURE`, the gate waits for an allowed frame to paint and for the Flutter engine to report its raster completion. This avoids clearing protection merely because an animation callback fired. Timing reports can be batched; allowance may therefore lag transition completion. While waiting, a cancellable retry requests another safe frame so an idle or dropped frame does not strand release. Missing reports retain protection; the retry never grants permission on a timeout.

This guarantees that the supported Flutter subtree's first protected displayed frame is withheld until the native protection request succeeds. **NavigatorObserver alone does not provide this guarantee.** The root gate, acknowledged window policy, route visibility tracking and raster-completion release work together. Protection still relies on Android honoring FLAG_SECURE; emulator sampling is not a formal proof of every device's compositor behavior.

Policy changes cannot retract screenshots or frames already produced while content was allowed. Await policy setters before introducing sensitive data into an otherwise unchanged route. A setter that enables screenshots can wait for a safe rasterized frame, including until foreground rendering resumes if the app is paused.

## Native startup and lifecycle

Both Dart and native defaults are blocked. Initialize before `runApp`. For the native launch window, apply protection before Flutter attachment in your Activity and use a non-sensitive splash theme:

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    super.onCreate(savedInstanceState)
}
```

The example includes this one-time native setup. Kotlin applies policy on the main thread and reapplies the latest state when the same engine attaches to a recreated Activity. A new engine/process starts blocked; restore backend policy explicitly. Disposal leaves the last window secure and releases Activity references. The plugin owns the window flag; other code must not independently clear it.

Native failures keep the gate closed. Awaited setters propagate `PlatformException`; asynchronous navigation failures are reported through `FlutterError.reportError`. A successful subsequent policy request can recover the gate. Do not bypass the gate to display an error: use non-sensitive UI outside it if required. There is no automatic fail-open fallback.

## Navigation support and limits

| Integration | Support |
|---|---|
| Navigator 1.0 named routes | Supported with the root builder and observer. Push/pop/replacement/removal, initial routes, system back and restorable named routes use the same gate. |
| Custom routes | Qualified routes extend `TransitionRoute`, honor Flutter's animation/completion and opacity contracts, and provide stable RouteSettings names. Unnamed routes remain protected. Arbitrary non-transition overlays/custom route implementations are not qualified. |
| Predictive back | Flutter transition routes that notify Navigator user-gesture callbacks are supported, including cancellation. For Android predictive animations configure `PredictiveBackPageTransitionsBuilder` centrally and enable the Android back callback as required by your Flutter/Android configuration. Native progress events require supported Android versions (API 34+); ordinary back continues to work on older APIs. |
| Navigator 2.0 | Wrap the root Navigator with the builder and attach its observer. Pages must expose stable `name` values. Change Page identity/key when its policy identity changes; renaming the same Route in place is not an observer notification. Arbitrary RouterDelegates are not automatically supported. |
| go_router | Use `MaterialApp.router.builder` for the gate, root router `observers` for the observer, and centrally supplied named Pages (for example `MaterialPage(key: state.pageKey, name: '/transfer', child: ...)`). URI paths and GoRoute names are not assumed to be RouteSettings names. This is a supported integration contract, not a claim that every router configuration/version is verified. |
| Nested Navigators / ShellRoute branches | Their route state is not automatically aggregated. Keep global screenshots disabled for that UI, or protect the entire containing root route. Do not attach the singleton observer to multiple Navigators. |
| Native platform views / separate windows | The paint gate does not control independently composited native surfaces, additional Activities, or UI outside its subtree. Keep those windows secure before creating sensitive native content; the automatic Flutter first-paint guarantee does not cover them. |

The emulator matrix qualifies Navigator 1.0 on one engine. Navigator 2.0 and go_router are documented integration contracts, not separately qualified router applications. Multiple engines sharing a window are outside this contract.

The gate temporarily withholds the complete Flutter subtree; it is not a selective screenshot-masking API. There are no capture listeners, screenshot/recording detection features, or iOS implementation.

- [Example root setup](example/lib/main.dart)
- [Automatic navigation results](docs/AUTOMATIC_ROUTE_PROTECTION.md)
- [Previous rebuild baseline](docs/VERIFICATION.md)
- [Android FLAG_SECURE](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_SECURE)
- [Flutter NavigatorObserver](https://api.flutter.dev/flutter/widgets/NavigatorObserver-class.html)
