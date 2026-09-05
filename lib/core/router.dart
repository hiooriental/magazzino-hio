import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db.dart';
import '../features/auth/accesso_screen.dart';
import '../features/cruscotto/cruscotto_screen.dart';
import '../features/documenti/documenti_screen.dart';
import '../features/documenti/documento_screen.dart';
import '../features/documenti/nuovo_documento_screen.dart';
import '../features/food_cost/food_cost_screen.dart';
import '../features/lavorazioni/lavorazione_screen.dart';
import '../features/lavorazioni/lavorazioni_screen.dart';
import '../features/scorte/scorte_screen.dart';

/// Sveglia GoRouter quando l'utente entra o esce.
///
/// Senza, dopo l'accesso resteresti sulla schermata di login finché non
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
  initialLocation: '/',
  refreshListenable: _CambioAccesso(),
  redirect: (context, state) {
    final suAccesso = state.matchedLocation == '/accesso';
    if (!Db.autenticato) return suAccesso ? null : '/accesso';
    if (suAccesso) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/accesso', builder: (_, __) => const AccessoScreen()),

    // Il cruscotto è la radice: è la schermata che si apre decine di volte
    // al giorno, e quella da cui si capisce se c'è qualcosa che non va.
    GoRoute(path: '/', builder: (_, __) => const CruscottoScreen()),

    GoRoute(
      path: '/documenti',
      builder: (_, __) => const DocumentiScreen(),
      routes: [
        // Prima di ':id': GoRouter prova le rotte nell'ordine in cui sono
        // scritte, e altrimenti "nuovo" verrebbe letto come l'id di un
        // documento inesistente.
        GoRoute(
            path: 'nuovo', builder: (_, __) => const NuovoDocumentoScreen()),
        GoRoute(
          path: ':id',
          builder: (_, s) =>
              DocumentoScreen(documentoId: s.pathParameters['id']!),
        ),
      ],
    ),

    GoRoute(path: '/scorte', builder: (_, __) => const ScorteScreen()),

    GoRoute(
      path: '/lavorazioni',
      builder: (_, __) => const LavorazioniScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, s) => LavorazioneScreen(id: s.pathParameters['id']!),
        ),
      ],
    ),

    GoRoute(path: '/food-cost', builder: (_, __) => const FoodCostScreen()),
  ],
);
