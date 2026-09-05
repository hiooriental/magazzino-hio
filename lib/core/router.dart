import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db.dart';
import '../features/auth/accesso_screen.dart';
import '../features/documenti/documenti_screen.dart';
import '../features/documenti/documento_screen.dart';
import '../features/documenti/nuovo_documento_screen.dart';

/// Sveglia GoRouter quando l'utente entra o esce.
///
/// Senza, dopo l'accesso resteresti sulla schermata di login finche' non
/// tocchi qualcosa: il redirect verrebbe valutato solo alla navigazione
/// successiva.
class _CambioAccesso extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  _CambioAccesso() {
    _sub = Db.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final router = GoRouter(
  initialLocation: '/documenti',
  refreshListenable: _CambioAccesso(),
  redirect: (context, state) {
    final suAccesso = state.matchedLocation == '/accesso';
    if (!Db.autenticato) return suAccesso ? null : '/accesso';
    if (suAccesso) return '/documenti';
    return null;
  },
  routes: [
    GoRoute(
      path: '/accesso',
      builder: (_, __) => const AccessoScreen(),
    ),
    GoRoute(
      path: '/documenti',
      builder: (_, __) => const DocumentiScreen(),
      routes: [
        // Prima di ':id': GoRouter prova le rotte nell'ordine in cui sono
        // scritte, e altrimenti "nuovo" verrebbe letto come l'id di un
        // documento inesistente.
        GoRoute(
          path: 'nuovo',
          builder: (_, __) => const NuovoDocumentoScreen(),
        ),
        GoRoute(
          path: ':id',
          builder: (_, stato) =>
              DocumentoScreen(documentoId: stato.pathParameters['id']!),
        ),
      ],
    ),
  ],
);
