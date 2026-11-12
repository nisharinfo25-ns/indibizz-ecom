import 'dart:async';

import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  Object? bootstrapError;
  try {
    await IndiBizz.initialize();
  } catch (error) {
    bootstrapError = error;
  }
  runApp(IndiBizzDeliveryApp(bootstrapError: bootstrapError));
}

class IndiBizzDeliveryApp extends StatefulWidget {
  const IndiBizzDeliveryApp({super.key, this.bootstrapError});
  final Object? bootstrapError;

  @override
  State<IndiBizzDeliveryApp> createState() => _IndiBizzDeliveryAppState();
}

class _IndiBizzDeliveryAppState extends State<IndiBizzDeliveryApp> {
  AuthController? _auth;

  @override
  void initState() {
    super.initState();
    if (widget.bootstrapError == null) {
      _auth = IndiBizz.authController();
      unawaited(_auth!.initialize());
    }
  }

  @override
  void dispose() {
    _auth?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'IndiaBizz Delivery',
        debugShowCheckedModeBanner: false,
        theme: IndiBizzTheme.light(),
        darkTheme: IndiBizzTheme.dark(),
        themeMode: ThemeController.instance.mode,
        home: widget.bootstrapError != null
            ? SetupNotice(
                appName: 'IndiaBizz Delivery',
                roleLabel: 'Delivery Fleet Workspace',
                error: widget.bootstrapError.toString(),
              )
            : AuthGate(
                controller: _auth!,
                allowedRoles: const {'OWN_DELIVERY_STAFF', 'PARTNER_DELIVERY_STAFF', 'PARTNER_ADMIN'},
                allowActivation: true,
                tagline: 'Deliver with certainty. Collect cash with precision.',
                purpose: 'delivery',
                builder: (context, profile) => DeliveryConsole(profile: profile, auth: _auth!),
              ),
      ),
    );
  }
}
