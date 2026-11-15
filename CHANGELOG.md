## Unreleased

Production cleanup: removed historical research/evidence and emulator fault-injection tooling; retained local path integration and regression tests. Documented an unresolved pending-release-on-gate-detach security issue without changing runtime behavior.

Automatic root navigation protection via `FlutterScreenProtection.builder` plus the observer. Existing navigation calls remain unchanged. Protected Flutter paint waits for native acknowledgement; allowance waits for a safe rasterized frame. Adds fail-closed errors, stale-response handling and predictive-gesture tracking.

## 0.1.0

Breaking Android-only rebuild: global screenshot policy, named-route protection, fail-closed startup, transition tracking and native FLAG_SECURE lifecycle handling. Removed capture detection, selective-rendering experiments and iOS support.
