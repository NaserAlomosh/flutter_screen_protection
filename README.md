# Flutter Screen Protection

An Android and iOS Flutter plugin project for privacy-sensitive screens in banking, fintech, and other apps. The goal is to help apps respond to capture signals and hide selected fields while keeping the rest of the interface usable.

**Development status:** The current `0.0.1` scaffold exposes `getPlatformVersion()`. Capture events, widget protection, and window privacy are planned and pending design review.

| Planned capability | Android | iOS |
| --- | --- | --- |
| Screenshot notification | Android 14+ for supported screenshot gestures | iOS 15+ target |
| Live capture state | Android 15+ reports app visibility in recording | iOS 15+ target, with scene-scoped detection from iOS 17 |
| Mask, blur, or replace selected Flutter content | Yes, with configurable fallback | Yes, with configurable fallback |
| Optional window and app-switcher privacy | Secure window and supported Recents controls | Background snapshot overlay |

Screenshot notifications arrive after capture. Reactive masking can take effect only after the signal reaches Flutter and a frame renders. Blur can leave data recognizable. Apps that need to keep a value out of captured output should keep it off the screen or use a separately validated platform control where available. See [security limitations](docs/SECURITY_LIMITATIONS.md).

## Planned API

The following sketch is for design review.

```dart
final controller = FlutterScreenProtectionController();
await controller.initialize();

final subscription = controller.captureEvents.listen((event) {
  if (event is ScreenshotTaken) {
    // Show an informational message.
  }
});

final field = SensitiveContent(
  controller: controller,
  protection: SensitiveProtection.mask,
  child: const Text('12,450.75 JOD'),
);

// The owner cancels its subscription and disposes the controller on teardown.
```

## Project documentation

- [Requirements](PROJECT_REQUIREMENTS.md), [implementation roadmap](IMPLEMENTATION_MASTER_PLAN.md), and [engineering backlog](TASKS.md)
- [Repository audit and architecture](docs/ARCHITECTURE.md), [API design](docs/API_DESIGN.md), and [decision register](docs/DECISION_REGISTER.md)
- [Platform compatibility](docs/PLATFORM_COMPATIBILITY.md), [security limitations](docs/SECURITY_LIMITATIONS.md), [testing strategy](docs/TESTING_STRATEGY.md), and [release plan](docs/RELEASE_PLAN.md)

## Contributing

Review the roadmap and decision register before starting implementation. Reference the relevant requirement and task in proposed changes. Use synthetic fixtures and record device, OS build, and capture method for platform evidence. The license is currently a placeholder and must be resolved before distribution.
