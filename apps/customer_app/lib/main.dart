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
  runApp(IndiBizzCustomerApp(bootstrapError: bootstrapError));
}

class IndiBizzCustomerApp extends StatefulWidget {
  const IndiBizzCustomerApp({super.key, this.bootstrapError});
  final Object? bootstrapError;

  @override
  State<IndiBizzCustomerApp> createState() => _IndiBizzCustomerAppState();
}

class _IndiBizzCustomerAppState extends State<IndiBizzCustomerApp> {
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
        title: 'IndiaBizz Shopping',
        debugShowCheckedModeBanner: false,
        theme: IndiBizzTheme.light(),
        darkTheme: IndiBizzTheme.dark(),
        themeMode: ThemeController.instance.mode,
        home: widget.bootstrapError != null
            ? SetupNotice(
                appName: 'IndiaBizz Shopping',
                roleLabel: 'Customer Store',
                error: widget.bootstrapError.toString(),
              )
            : AuthGate(
                controller: _auth!,
                allowedRoles: const {'CUSTOMER', 'OWNER'},
                allowActivation: false,
                tagline: 'Direct delivery. Verified doorstep cash.',
                purpose: 'customer',
                builder: (context, profile) => CustomerConsole(profile: profile, auth: _auth!),
              ),
      ),
    );
  }
}
