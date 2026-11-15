# FSP-018 cleanup audit

## Classification and retained structure

```text
android/                 Production Kotlin, manifest, Gradle configuration, JVM tests
lib/                     Unchanged public API and rendering/protection implementation
test/                    Policy and automatic navigation regression tests
example/                 Minimal Android app, resources, Gradle wrapper, widget test
pubspec.yaml             Android plugin registration and Flutter dependencies
README.md                Local installation and production integration contract
CHANGELOG.md, LICENSE    Package history and licensing
analysis_options.yaml    Shared lint configuration
.metadata                Flutter project metadata
.gitignore, .pubignore   Generated/local artifacts and backup exclusions
CLEANUP_AUDIT.md          Cleanup decisions, verification and unresolved issue
```

Removed tracked docs/archive, docs/evidence, historical verification reports, tool validation scripts, example/integration_test, and debug ValidationActivity. Removed its manifest registration. These files formed a standalone emulator research/validation harness; production code and retained unit/widget tests do not import them. The debug manifest retains INTERNET for Flutter tooling. Android resources, Gradle configuration/wrapper, Kotlin test dependencies and Flutter metadata are retained.

Removed the example's unused integration_test SDK development dependency and refreshed its lockfile. Runtime dependencies remain Flutter only. Retained flutter_test/flutter_lints and Kotlin/Mockito test dependencies. The existing optional protectNavigation helper remains because callers and retained regression tests use it; removing it would break compatibility. All five requested public API entries remain unchanged.

Tracked artifacts were removed individually so unrelated untracked data was not swept away. Local .rebuild-backup, IDE preferences and unrelated untracked files were preserved and excluded from distribution. Flutter clean removed generated build caches before verification; validation necessarily regenerated ignored build/cache files, which are cleaned again after checks. Machine-specific local.properties are generated local configuration, not tracked package requirements.

## Separate security finding: pending release on gate detach

**Unresolved; production integration risk.** In _RenderProtectionGate.detach(), detaching the last gate removes the timing callback and calls release.finish(). finish() cancels its retry and completes the same Future used for successful raster acknowledgement. The suspended _sync() can resume with an unchanged revision and blocked=false, then invoke native setProtection(false), despite no confirmed safe raster frame. A retained protected frame could therefore lose FLAG_SECURE during root teardown/replacement.

Normal acknowledgement and supersession paths also call finish(), but supersession changes the revision and suppresses the old request. Detach does not provide that distinction. A future security fix should separate cancellation from successful raster confirmation and invalidate the pending policy revision on detach, with a regression reproducing detach before timing acknowledgement. This is source-level analysis; it is not a newly executed device exploit test.

Behavior is deliberately unchanged under the cleanup instruction. Keep the root gate mounted for the engine lifetime; this workaround is not a proof of safety for arbitrary teardown. Do not treat passing existing tests as coverage of this gap.

Native Activity/engine cleanup retains fail-closed defaults and releases Activity/channel references. The rendering timing callback is removed on final detach and the retry timer is canceled. No new runtime logging, dependencies, or routing features were added. Missing raster acknowledgement while mounted remains fail closed. Existing platform/router limitations are documented in README.

## Verification

- Root flutter pub get, flutter analyze: PASS; 13 Flutter tests PASS.
- Example flutter pub get, flutter analyze: PASS; 1 widget test PASS; debug APK build PASS.
- Kotlin JVM tests: 2 PASS.
- Temporary external consumer: local path dependency resolves; Android debug APK build PASS; generated Android registrant includes FlutterScreenProtectionPlugin. Consumer uses minSdk 29, Gradle 8.14, AGP 8.11.1 and Kotlin 2.2.20 (aligned to the working example after the fresh template stalled downloading Gradle 8.12). This is a compile/registration check, not runtime device verification.
- Production source and retained regression test diff: unchanged.
- No emulator/physical-device tests executed during this cleanup. Historical evidence was removed as requested, not relabeled as current verification.
- Branch development; no commit, push, merge, tag, or publication.

The temporary consumer and verification logs are under /private/tmp/fsp018-* and are not package dependencies or repository deliverables. The consumer alone uses an absolute temporary test path; application integration uses the relative path shown in README. Flutter/Gradle dependencies still require ordinary SDK/cache/repository availability, but plugin consumption does not require GitHub or pub.dev publication.

Removed lockfile-only transitive development packages: file, flutter_driver, fuchsia_remote_debug_protocol, platform, process, sync_http, web and webdriver, in addition to integration_test.

Final Git summary: 3,621 tracked artifact files deleted; 8 tracked configuration/documentation/lock files modified; this audit is new. Production source and regression tests have no changes. git diff --check passes. Large deletion counts are primarily the historical screenshot/log collection, not runtime code.
