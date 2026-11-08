# Release plan

This plan covers GitHub and pub.dev. Phase 7 prepares an independently reviewable release candidate. Publishing and tagging require a separate maintainer decision.

## Readiness gates

1. **Ownership and metadata.** Select an open-source license and replace the placeholder. Confirm package name availability and publishing account. Set repository, description, issue tracker, homepage and podspec details. Choose the first release version under the maintainer's versioning policy and complete the changelog.
2. **Toolchains.** Declare compatible Flutter and Dart floors after testing the pair. Document Android build requirements, iOS deployment and CocoaPods requirements, and scene integration. Confirm the minimum and current toolchains in CI, including a current Xcode job. Evaluate Apple privacy manifest requirements against the actual final APIs and package it if required.
3. **Quality and security.** Require passing analysis, Flutter and native tests, example builds, clean-install smoke tests, and physical evidence per the [testing strategy](TESTING_STRATEGY.md). Inspect Android merged permissions, iOS packaging, logging and release contents. Security reviewer checks compatibility and capture claims against evidence. Omit optional features whose gates remain open.
4. **Package rehearsal.** From a clean candidate checkout run `dart pub publish --dry-run`, review package contents and warnings, verify the example can consume the packaged candidate, and validate README links. Inspect the planned GitHub release notes for capability and migration accuracy.
5. **Authorization.** Maintainer approves a specific candidate revision, version, evidence set and release notes before any tag, GitHub release or pub.dev publication. Keep release credentials and workflows restricted to approved publisher ownership.
6. **After approval.** Maintainer follows the authorized publication order, checks the public listing and documentation, and verifies a fresh example install. For regressions, document impact and issue a corrected version under pub.dev's version and retraction rules. Track affected OS and capture methods in GitHub.

[Pub publishing workflow](https://dart.dev/tools/pub/publishing), [Dart package metadata](https://dart.dev/tools/pub/pubspec).

The audit found placeholder license, changelog and package metadata, plus no tracked CI workflow. The plan leaves those release tasks for Phase 7 and leaves distribution outside the current documentation phase.
