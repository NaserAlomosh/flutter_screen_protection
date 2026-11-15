import 'package:flutter/material.dart';
import 'package:flutter_screen_protection/flutter_screen_protection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterScreenProtection.initialize(protectedRoutes: protectedRoutes);
  runApp(const ProtectionExample());
}

const protectedRoutes = [
  '/login',
  '/account-details',
  '/transfer',
  '/card-details',
];

class ProtectionExample extends StatefulWidget {
  const ProtectionExample({super.key});
  @override
  State<ProtectionExample> createState() => _ProtectionExampleState();
}

class _ProtectionExampleState extends State<ProtectionExample> {
  bool enabled = false;
  bool protectHome = false;
  String? error;

  Future<void> update(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    restorationScopeId: 'example',
    navigatorObservers: [FlutterScreenProtection.navigatorObserver],
    initialRoute: '/home',
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(settings.name ?? 'Unnamed')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'SCREEN CONTENT: ${settings.name}',
              style: const TextStyle(fontSize: 24),
            ),
            const Text('Local mock backend • developer demonstration controls'),
            SwitchListTile(
              title: const Text('Backend: screenshots enabled'),
              value: enabled,
              onChanged: (value) => update(() async {
                final response = {'screenshotsEnabled': value};
                await FlutterScreenProtection.setScreenshotsEnabled(
                  response['screenshotsEnabled']!,
                );
                setState(() => enabled = value);
              }),
            ),
            SwitchListTile(
              title: const Text('Protect /home at runtime'),
              value: protectHome,
              onChanged: (value) => update(() async {
                await FlutterScreenProtection.setProtectedRoutes([
                  ...protectedRoutes,
                  if (value) '/home',
                ]);
                setState(() => protectHome = value);
              }),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            for (final route in [
              '/home',
              '/login',
              '/account-details',
              '/transfer',
              '/transactions',
            ])
              ElevatedButton(
                onPressed: () => update(
                  () => FlutterScreenProtection.protectNavigation(() {
                    Navigator.of(context).restorablePushNamed(route);
                  }),
                ),
                child: Text('Open $route'),
              ),
            Text(
              'Protected routes: ${[...protectedRoutes, if (protectHome) '/home'].join(', ')}',
            ),
          ],
        ),
      ),
    ),
  );
}
