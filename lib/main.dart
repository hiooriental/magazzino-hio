import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router.dart';
import 'shared/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Stesse credenziali del gestionale prenotazioni: e' lo stesso progetto
  // Supabase, il magazzino vive solo in un altro schema.
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const ProviderScope(child: AppMagazzino()));
}

class AppMagazzino extends StatelessWidget {
  const AppMagazzino({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Magazzino HIO',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
        locale: const Locale('it', 'IT'),
        supportedLocales: const [Locale('it', 'IT')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      );
}
