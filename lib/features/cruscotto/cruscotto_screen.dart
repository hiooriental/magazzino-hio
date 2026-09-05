import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';

/// La prima schermata: cosa c'è che non va, e cosa c'è da fare.
///
/// Ordine voluto: prima gli allarmi, poi il lavoro arretrato, poi i numeri.
/// Un cruscotto che apre con «valore di magazzino € 12.340» è un cruscotto
/// che nessuno guarda, perché quel numero non chiede niente a nessuno.
///
/// Le tessere che valgono zero spariscono invece di mostrare uno zero: una
/// schermata piena di zeri verdi insegna a non leggerla.
final cruscottoProvider = FutureProvider.autoDispose((ref) async {
  final s = await ref.watch(sessioneProvider.future);
  return repo.cruscotto(s.organizzazioneId);
});

class CruscottoScreen extends ConsumerWidget {
  const CruscottoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessione = ref.watch(sessioneProvider);
    final dati = ref.watch(cruscottoProvider);

    return Scaffold(
      drawer: const AppDrawer(attiva: '/'),
      appBar: AppBar(
        title: const Text('Magazzino'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(cruscottoProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/documenti/nuovo'),
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Fotografa'),
      ),
      body: dati.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e is NonAbilitato
                  ? 'La tua utenza non è ancora abilitata al magazzino.'
                  : 'Non riesco a leggere i dati.\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        data: (c) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(cruscottoProvider),
          child: ContenutoCentrato(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (sessione.hasValue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      sessione.value!.organizzazione,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ..._sezione(
                  context,
                  titolo: 'Da guardare subito',
                  tessere: [
                    _T(c, 'da_abbattere', 'da abbattere', AppColors.accent,
                        Icons.ac_unit, '/scorte',
                        nota: 'Pesce crudo entrato e non ancora abbattuto'),
                    _T(c, 'lotti_scaduti', 'lotti scaduti', AppColors.accent,
                        Icons.dangerous_outlined, '/scorte'),
                    _T(c, 'esauriti', 'esauriti', AppColors.accent,
                        Icons.remove_shopping_cart_outlined, '/scorte'),
                    _T(c, 'critici', 'sotto scorta', AppColors.sottoScorta,
                        Icons.trending_down, '/scorte'),
                    _T(c, 'lotti_in_scadenza', 'in scadenza',
                        AppColors.inScadenza, Icons.schedule, '/scorte'),
                    _T(c, 'rincari_forti', 'rincari oltre il 10%',
                        AppColors.inScadenza, Icons.arrow_upward, '/scorte'),
                  ],
                ),
                ..._sezione(
                  context,
                  titolo: 'Da fare',
                  tessere: [
                    _T(c, 'righe_da_abbinare', 'righe da abbinare',
                        AppColors.rigaProposta, Icons.link, '/documenti'),
                    _T(
                        c,
                        'documenti_aperti',
                        'documenti aperti',
                        AppColors.rigaProposta,
                        Icons.receipt_long_outlined,
                        '/documenti'),
                    _T(
                        c,
                        'lavorazioni_aperte',
                        'lavorazioni aperte',
                        AppColors.rigaProposta,
                        Icons.content_cut,
                        '/lavorazioni'),
                    _T(c, 'inventari_aperti', 'inventari aperti',
                        AppColors.rigaProposta, Icons.checklist, '/scorte'),
                    _T(
                        c,
                        'prodotti_da_collegare',
                        'prodotti senza ricetta',
                        AppColors.rigaProposta,
                        Icons.restaurant_menu,
                        '/food-cost'),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Numeri', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _Numeri(c),
                const SizedBox(height: 20),
                _Nota(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Mostra una sezione solo se almeno una tessera ha un valore.
  List<Widget> _sezione(
    BuildContext context, {
    required String titolo,
    required List<_T> tessere,
  }) {
    final vive = tessere.where((t) => t.valore > 0).toList();
    if (vive.isEmpty) return const [];
    return [
      Text(titolo, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: vive),
      const SizedBox(height: 20),
    ];
  }
}

/// Una tessera. Compare solo se il suo numero è maggiore di zero.
class _T extends StatelessWidget {
  final int valore;
  final String etichetta;
  final Color colore;
  final IconData icona;
  final String rotta;
  final String? nota;

  _T(Map<String, dynamic> c, String campo, this.etichetta, this.colore,
      this.icona, this.rotta,
      {this.nota})
      : valore = (c[campo] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(rotta),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colore.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colore.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icona, size: 18, color: colore),
                  const Spacer(),
                  Text('$valore',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: colore)),
                ],
              ),
              const SizedBox(height: 2),
              Text(etichetta,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
              if (nota != null) ...[
                const SizedBox(height: 4),
                Text(nota!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Numeri extends StatelessWidget {
  final Map<String, dynamic> c;
  const _Numeri(this.c);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _riga(
                  'Valore del magazzino', euro(c['valore_magazzino'] as num?)),
              const Divider(height: 20),
              _riga('Acquisti del mese', euro(c['acquisti_mese'] as num?)),
              _riga('Consumo del mese', euro(c['consumo_mese'] as num?)),
              const Divider(height: 20),
              _riga('Ingredienti in anagrafica',
                  '${(c['ingredienti'] as num?)?.toInt() ?? 0}'),
              _riga('Prodotti a menù',
                  '${(c['prodotti'] as num?)?.toInt() ?? 0}'),
              _riga('…di cui con ricetta',
                  '${(c['prodotti_con_ricetta'] as num?)?.toInt() ?? 0}'),
            ],
          ),
        ),
      );

  Widget _riga(String e, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(e,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13.5)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Quando non c'è nulla di urgente, dirlo. Una schermata vuota senza
/// spiegazione sembra un guasto.
class _Nota extends StatelessWidget {
  final Map<String, dynamic> c;
  const _Nota(this.c);

  int get _urgenti => [
        'da_abbattere',
        'lotti_scaduti',
        'esauriti',
        'critici',
        'righe_da_abbinare',
        'documenti_aperti',
        'lavorazioni_aperte',
        'prodotti_da_collegare'
      ].fold(0, (s, k) => s + ((c[k] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) {
    if (_urgenti > 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.statoConfermatoSfondo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.statoConfermato),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Niente in sospeso: nessun documento aperto, nessuna scorta '
              'sotto soglia, nessun lotto in scadenza.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}
