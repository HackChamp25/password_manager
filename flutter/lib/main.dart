import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/vault_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VaultProvider(),
      child: MaterialApp(
        title: '🔐 Secure Password Manager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFF00d9ff),
            secondary: const Color(0xFF7c3aed),
            tertiary: const Color(0xFF10b981),
            error: const Color(0xFFef4444),
            surface: const Color(0xFF1a202c),
            background: const Color(0xFF0f172a),
          ),
          scaffoldBackgroundColor: const Color(0xFF0f172a),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1a202c),
            elevation: 0,
            centerTitle: true,
            titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00d9ff),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF2d3748),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00d9ff), width: 2),
            ),
            labelStyle: const TextStyle(color: Color(0xFFcbd5e0)),
            hintStyle: const TextStyle(color: Color(0xFF718096)),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00d9ff),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00d9ff),
              side: const BorderSide(color: Color(0xFF2d3748)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        home: Consumer<VaultProvider>(
          builder: (context, vaultProvider, _) {
            return vaultProvider.isUnlocked ? const HomeScreen() : const LoginScreen();
          },
        ),
      ),
    );
  }
}
