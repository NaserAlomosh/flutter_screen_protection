# Android example

Run `flutter run` on Android API 29+. The app configures `FlutterScreenProtection.builder` and `navigatorObserver` once on MaterialApp. Home, Login, Account Details, Transfer and Transactions use ordinary Navigator.pushNamed calls; there are no per-screen guards.

The switches simulate backend screenshot policy and runtime protected-route configuration. Startup is blocked until the backend switch is enabled. MainActivity applies FLAG_SECURE before Flutter attachment. ValidationActivity is debug-only and provides lifecycle and native fault-injection controls for the integration tests.
