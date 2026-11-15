import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Android screenshot policy matrix', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
    final requests = StreamIterator<HttpRequest>(server);
    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });
    final key = GlobalKey<NavigatorState>();
    await FlutterScreenProtection.initialize(protectedRoutes: ['/transfer']);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [FlutterScreenProtection.navigatorObserver],
        initialRoute: '/home',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(
            backgroundColor: const Color(0xff20c060),
            body: Center(
              child: Text(
                'VISIBLE CONTENT ${settings.name}',
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> evidence(String name, bool blocked) async {
      await tester.pumpAndSettle();
      // External ADB runner captures the real composed display during this interval.
      // ignore: avoid_print
      print('FSP_EVIDENCE $name ${blocked ? "BLOCKED" : "ALLOWED"}');
      await tester.runAsync(() async {
        if (!await requests.moveNext().timeout(const Duration(seconds: 60))) {
          throw StateError('Evidence runner disconnected');
        }
        await requests.current.response.close();
      });
    }

    await evidence('startup', true);
    await FlutterScreenProtection.setScreenshotsEnabled(true);
    await evidence('global_enabled_home', false);
    await FlutterScreenProtection.setScreenshotsEnabled(false);
    await evidence('global_disabled', true);
    await FlutterScreenProtection.setScreenshotsEnabled(true);
    await evidence('backend_reenabled', false);
    // Guard before push; endOfFrame is driven by the test below.
    final navigation = FlutterScreenProtection.protectNavigation(() {
      key.currentState!.pushNamed('/transfer');
    });
    await tester.pumpAndSettle();
    await navigation;
    await evidence('protected_transfer', true);
    key.currentState!.pop();
    await evidence('pop_home', false);
    key.currentState!.pushNamed('/transfer');
    await evidence('system_back', false);
    await FlutterScreenProtection.setProtectedRoutes(['/home', '/transfer']);
    await evidence('route_list_add', true);
    await FlutterScreenProtection.setProtectedRoutes(['/transfer']);
    await evidence('route_list_remove', false);
    key.currentState!.pushReplacementNamed('/transfer');
    await evidence('replacement_protected', true);
    key.currentState!.pushNamedAndRemoveUntil('/home', (_) => false);
    await evidence('remove_until_home', false);
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/transfer'),
      builder: (_) => const Text('transfer'),
    );
    key.currentState!.push(route);
    await tester.pumpAndSettle();
    key.currentState!.removeRoute(route);
    await evidence('remove_route', false);
    key.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('unnamed')),
    );
    await evidence('unnamed', true);
    key.currentState!.pop();
    await FlutterScreenProtection.setScreenshotsEnabled(false);
    key.currentState!.pushNamed('/transfer');
    key.currentState!.pop();
    await evidence('global_precedence_rapid_navigation', true);
    await Future.wait(
      List.generate(
        20,
        (i) => FlutterScreenProtection.setScreenshotsEnabled(i.isOdd),
      ),
    );
    await evidence('rapid_updates_final_allowed', false);
    await evidence('lifecycle_allowed', false);
    await FlutterScreenProtection.setScreenshotsEnabled(false);
    await evidence('lifecycle_secure', true);
    // ignore: avoid_print
    print('FSP_MATRIX_DONE');
  });
}
