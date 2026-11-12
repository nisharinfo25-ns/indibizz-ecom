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
  runApp(IndiBizzSellerApp(bootstrapError: bootstrapError));
}

class IndiBizzSellerApp extends StatefulWidget {
  const IndiBizzSellerApp({super.key, this.bootstrapError});
  final Object? bootstrapError;

  @override
  State<IndiBizzSellerApp> createState() => _IndiBizzSellerAppState();
}

class _IndiBizzSellerAppState extends State<IndiBizzSellerApp> {
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
        title: 'IndiaBizz Seller',
        debugShowCheckedModeBanner: false,
        theme: IndiBizzTheme.light(),
        darkTheme: IndiBizzTheme.dark(),
        themeMode: ThemeController.instance.mode,
        home: widget.bootstrapError != null
            ? SetupNotice(
                appName: 'IndiaBizz Seller',
                roleLabel: 'Owner workspace',
                error: widget.bootstrapError.toString(),
              )
            : AuthGate(
                controller: _auth!,
                allowedRoles: const {'OWNER'},
                tagline: 'Run your store with certainty.',
                purpose: 'owner',
                builder: (context, profile) => SellerConsole(profile: profile, auth: _auth!),
              ),
      ),
    );
  }
}
