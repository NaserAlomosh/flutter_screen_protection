# flutter_screen_protection

Android screenshot protection using a global backend policy, protected route names, and `FLAG_SECURE`. Requires Android API 29+, Flutter 3.35.4+ and Dart 3.9.2+.

## Local installation

```yaml
dependencies:
  flutter_screen_protection:
    path: ../flutter_screen_protection
```

Set `minSdk = 29` (or higher) in your application's Android `defaultConfig`, then run `flutter pub get`. The plugin needs no publication or GitHub access; Flutter and Gradle still need their normal SDK/dependency caches or repositories. There are no non-Flutter runtime package dependencies.

## Configure once

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterScreenProtection.initialize(
    screenshotsEnabled: true,
    protectedRoutes: ['/login', '/transfer', '/account-details', '/card-details'],
  );
  runApp(MaterialApp(
    builder: FlutterScreenProtection.builder,
    navigatorObservers: [FlutterScreenProtection.navigatorObserver],
    routes: existingRoutes, // Your existing routes or onGenerateRoute factory.
  ));
}
```

Both root properties are required. If you already use a builder, wrap its result with `FlutterScreenProtection.builder(context, existingBuilder(context, child))`.

Existing `Navigator.pushNamed`, `Navigator.pop`, and `Navigator.pushReplacementNamed` calls remain unchanged. No per-screen changes are required.

## Policies and public API

- `initialize({bool screenshotsEnabled = false, List<String> protectedRoutes = const []})`
- `setScreenshotsEnabled(bool enabled)`
- `setProtectedRoutes(List<String> routes)`
- `builder(BuildContext context, Widget? child)`
- `navigatorObserver`

The three policy methods return `Future<void>`. Global `false` always blocks screenshots, regardless of route. Route names match exactly and case-sensitively; unnamed routes and an empty Navigator fail closed. The route list is copied.

```dart
await FlutterScreenProtection.setScreenshotsEnabled(response.screenshotsEnabled);
await FlutterScreenProtection.setProtectedRoutes(['/login', '/transfer']);
```

Backend configuration is not fetched or persisted by the plugin. Await policy updates before introducing sensitive data into an otherwise unchanged route. The legacy `protectNavigation(VoidCallback)` helper remains for compatibility; root integration does not require it.

## Native startup

Apply startup protection in your application's Activity, before Flutter attachment, and use a non-sensitive splash theme:

```kotlin
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }
}
```

Native policy is reapplied when the engine attaches to a recreated Activity. A new engine starts blocked; restore backend configuration explicitly. The plugin owns the window flag: other code must not clear it independently.

## Security boundaries

The observer alone cannot guarantee first-frame protection. The root rendering gate excludes protected Flutter layers until the latest native secure request succeeds. It retains protection through outgoing transitions and gestures, and waits for safe raster completion before allowing screenshots. A repaint retry never grants permission based on elapsed time. Native failures close the gate; awaited setters propagate errors and observer failures use `FlutterError.reportError`. A later successful policy request can recover.

**Known unresolved issue:** detaching the last gate during a pending safe-frame release can complete that wait without raster confirmation and allow native protection to clear. Keep the root gate mounted for the engine lifetime. See [cleanup audit](CLEANUP_AUDIT.md) before production integration. This cleanup deliberately does not change security behavior.

Supported setup is one root Navigator with stable names and TransitionRoute-based routes honoring Flutter opacity/completion contracts. Navigator 2.0 requires named Pages and changed identity/key when policy identity changes. For go_router, wrap MaterialApp.router, attach the root observer, and centrally create named Pages; URI paths are not automatically route names. These router configurations are not universally qualified.

Nested Navigators are not aggregated: protect their containing root route or disable screenshots globally. Independent native platform views, separate windows, multiple engines sharing a window, and UI outside the gate are outside the first-frame guarantee. Rendering may continue offscreen while the gate excludes its layers. Missing raster reports or paused rendering can delay allowance. Android/OEM compositor behavior remains a platform dependency; no universal device guarantee is claimed. No iOS implementation or screenshot detection is provided.

## Development

Run `flutter analyze` and `flutter test`; the example uses the plugin through a local path dependency. Regression tests cover gate acknowledgement, errors, transitions, policy precedence, restoration and back navigation. Android unit tests are available through the example Gradle project.
