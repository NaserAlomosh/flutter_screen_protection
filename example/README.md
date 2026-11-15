# Android example

Run `flutter run` from this directory on Android API 29+. Home, Login, Account Details, Transfer and Transactions demonstrate global and named-route policies. The two switches simulate backend policy and runtime route configuration. No backend or end-user toggle is required by the plugin.

Startup is blocked until the mock backend switch is enabled. MainActivity applies FLAG_SECURE before Flutter attachment. Navigation uses the acknowledged pre-navigation guard. ValidationActivity is a debug-only host used to test a retained Flutter engine across Activity recreation.
