import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';
import '../../shared/widgets/scegli_ingrediente.dart';
import 'ingrediente_sheet.dart';

final ingredientiProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, soloAttivi) async {
  await ref.watch(sessioneProvider.future);
  return repo.ingredienti(soloAttivi: soloAttivi);
});

/// L'anagrafica degli ingredienti.
///
/// Raggruppata per categoria e con tre filtri che corrispondono a tre domande
/// vere: cosa preparo io, cosa va abbattuto, cosa ho spento.
class IngredientiScreen extends ConsumerStatefulWidget {
  const IngredientiScreen({super.key});

  @override
  ConsumerState<IngredientiScreen> createState() => _IngredientiScreenState();
}

class _IngredientiScreenState extends ConsumerState<IngredientiScreen> {
  final _cerca = TextEditingController();
  bool _soloSemilavorati = false;
  bool _soloAbbattimento = false;
  bool _ancheSpenti = false;

  @override
  void dispose() {
    _cerca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessione = ref.watch(sessioneProvider).valueOrNull;
    final elenco = ref.watch(ingredientiProvider(!_ancheSpenti));

    /// Apre la ricetta del semilavorato, creandola se non c'è ancora.
    Future<void> apriRicetta(Map<String, dynamic> i) async {
      if (sessione == null) return;
      var id = await repo.distintaDiIngrediente(i['id'] as String);
      if (id == null) {
        if (!context.mounted) return;
        final resa = await chiediNumero(
          context,
          titolo: 'Quanto ${i['nome']} esce da una preparazione?',
          etichetta: 'Resa in ${i['um_base']}',
          aiuto: 'Il peso finito, non la somma degli ingredienti.',
        );
        if (resa == null || resa <= 0) return;
        id = await repo.distintaAttiva(
          organizzazioneId: sessione.organizzazioneId,
          ingredienteId: i['id'] as String,
          quantitaProdotta: resa,
        );
      }
      if (context.mounted) context.go('/ricette/$id');
    }

    Future<void> apri([Map<String, dynamic>? i]) async {
      if (sessione == null) return;
      final cambiato = await apriIngrediente(
        context,
        ingrediente: i,
        organizzazioneId: sessione.organizzazioneId,
      );
      if (cambiato) ref.invalidate(ingredientiProvider);
    }

    return Scaffold(
      drawer: const AppDrawer(attiva: '/ingredienti'),
      appBar: AppBar(
        title: const Text('Ingredienti'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ingredientiProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: apri,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo'),
      ),
      body: ContenutoCentrato(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _cerca,
                    decoration: InputDecoration(
                      hintText: 'Cerca',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _cerca.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(_cerca.clear),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('Semilavorati'),
                          selected: _soloSemilavorati,
                          onSelected: (v) =>
                              setState(() => _soloSemilavorati = v),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Da abbattere'),
                          selected: _soloAbbattimento,
                          onSelected: (v) =>
                              setState(() => _soloAbbattimento = v),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Anche spenti'),
                          selected: _ancheSpenti,
                          onSelected: (v) => setState(() => _ancheSpenti = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: elenco.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('$e', textAlign: TextAlign.center),
                  ),
                ),
                data: (tutti) {
                  final q = _cerca.text.trim().toLowerCase();
                  final righe = tutti.where((i) {
                    if (_soloSemilavorati &&
                        i['prodotto_internamente'] != true) {
                      return false;
                    }
                    if (_soloAbbattimento &&
                        i['richiede_abbattimento'] != true) {
                      return false;
                    }
                    if (q.isEmpty) return true;
                    return (i['nome'] as String? ?? '')
                        .toLowerCase()
                        .contains(q);
                  }).toList();

                  if (tutti.isEmpty) {
                    return const _Messaggio(
                        'Nessun ingrediente.\n\nSi creano qui, oppure nascono '
                        'da soli abbinando le righe di una fattura.');
                  }
                  if (righe.isEmpty) {
                    return const _Messaggio('Nessun risultato.');
                  }

                  final gruppi = <String, List<Map<String, dynamic>>>{};
                  for (final i in righe) {
                    final c = (i['categoria_ingrediente'] as Map?)?['nome']
                            as String? ??
                        'Senza categoria';
                    gruppi.putIfAbsent(c, () => []).add(i);
                  }
                  final chiavi = gruppi.keys.toList()..sort();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    children: [
                      for (final c in chiavi) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(c,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.goldDark,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                    )),
                              ),
                              Text('${gruppi[c]!.length}',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        ...gruppi[c]!.map((i) => _Riga(
                              i: i,
                              onTap: () => apri(i),
                              onRicetta: i['prodotto_internamente'] == true
                                  ? () => apriRicetta(i)
                                  : null,
                            )),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  final Map<String, dynamic> i;
  final VoidCallback onTap;
  final VoidCallback? onRicetta;
  const _Riga({required this.i, required this.onTap, this.onRicetta});

  @override
  Widget build(BuildContext context) {
    final um = i['um_base'] as String? ?? '';
    final costo = i['costo_medio'] as num?;
    final spento = i['attivo'] == false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: spento ? 0.5 : 1,
        child: Card(
          child: ListTile(
            dense: true,
            title: Row(
              children: [
                Flexible(
                  child: Text(i['nome'] as String? ?? '',
                      overflow: TextOverflow.ellipsis),
                ),
                if (i['richiede_abbattimento'] == true) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.ac_unit, size: 14, color: AppColors.accent),
                ],
                if (i['prodotto_internamente'] == true) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.blender_outlined,
                      size: 14, color: AppColors.goldDark),
                ],
              ],
            ),
            subtitle: Text(
              [
                'in $um',
                // Il costo al chilo si legge, quello al grammo no.
                if (costo != null)
                  um == 'pz'
                      ? '${numeroIt(costo)} €/pz'
                      : '${numeroIt(num.parse((costo * 1000).toStringAsFixed(2)))} €/${um == 'g' ? 'kg' : 'l'}'
                else
                  'nessun costo ancora',
                if (spento) 'spento',
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Per un semilavorato la ricetta è la cosa che serve più
                // spesso: senza questa scorciatoia bisognerebbe uscire,
                // andare in Ricette e ritrovarlo lì.
                if (onRicetta != null)
                  IconButton(
                    tooltip: 'Ricetta',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.menu_book_outlined, size: 19),
                    color: AppColors.goldDark,
                    onPressed: onRicetta,
                  ),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.textMuted),
              ],
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _Messaggio extends StatelessWidget {
  final String testo;
  const _Messaggio(this.testo);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(testo,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
}
