import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_settings_provider.dart';
import 'providers/vault_provider.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/session_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettingsProvider>(
          create: (_) => AppSettingsProvider(),
        ),
        ChangeNotifierProvider<VaultProvider>(
          create: (_) => VaultProvider(),
        ),
      ],
      child: Consumer2<AppSettingsProvider, VaultProvider>(
        builder: (context, settings, vault, _) {
          return MaterialApp(
            title: 'Cipher Nest',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: vault.isUnlocked
                ? const SessionGuard(child: AppShell())
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
