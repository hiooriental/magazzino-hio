import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db.dart';
import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';

final foodCostProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);
  return repo.foodCost();
});

final daCollegareProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);
  return List<Map<String, dynamic>>.from(
      await Db.mag.from('prodotti_da_collegare').select().limit(100));
});

/// Quanto costa davvero ogni piatto.
///
/// Ordinato per incidenza decrescente: in cima i piatti che si mangiano il
/// margine. È l'ordine utile, non quello alfabetico.
class FoodCostScreen extends ConsumerStatefulWidget {
  const FoodCostScreen({super.key});

  @override
  ConsumerState<FoodCostScreen> createState() => _FoodCostScreenState();
}

class _FoodCostScreenState extends ConsumerState<FoodCostScreen> {
  bool _daCollegare = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(attiva: '/food-cost'),
      appBar: AppBar(
        title: const Text('Food cost'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(foodCostProvider);
              ref.invalidate(daCollegareProvider);
            },
          ),
        ],
      ),
      body: ContenutoCentrato(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Con ricetta')),
                  ButtonSegment(value: true, label: Text('Da collegare')),
                ],
                selected: {_daCollegare},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    setState(() => _daCollegare = s.first),
              ),
            ),
            Expanded(
                child:
                    _daCollegare ? const _DaCollegare() : const _ConRicetta()),
          ],
        ),
      ),
    );
  }
}

class _ConRicetta extends ConsumerWidget {
  const _ConRicetta();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(foodCostProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (righe) => righe.isEmpty
                ? const _Vuoto(
                    'Nessun prodotto ha ancora una ricetta.\n\nLe ricette si '
                    'costruiscono partendo dagli ingredienti già in anagrafica.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: righe.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _RigaCosto(righe[i]),
                  ),
          );
}

class _RigaCosto extends StatelessWidget {
  final Map<String, dynamic> r;
  const _RigaCosto(this.r);

  @override
  Widget build(BuildContext context) {
    final incidenza = r['incidenza_percentuale'] as num?;
    final senzaCosto = (r['componenti_senza_costo'] as num?)?.toInt() ?? 0;

    // Nella ristorazione un'incidenza sopra il 35% erode il margine; sotto il
    // 25% è ottima. Le soglie sono indicative e servono a far saltare
    // all'occhio i casi estremi, non a dare un voto.
    final colore = incidenza == null
        ? AppColors.textMuted
        : incidenza >= 40
            ? AppColors.accent
            : incidenza >= 32
                ? AppColors.inScadenza
                : AppColors.statoConfermato;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['prodotto'] as String? ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    'costo ${euro(r['costo'] as num?)} · '
                    'prezzo ${euro(r['prezzo_vendita'] as num?)} · '
                    'margine ${euro(r['margine'] as num?)}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  // Un costo calcolato su ingredienti senza prezzo è più
                  // basso del vero: dirlo, invece di lasciarlo credere.
                  if (senzaCosto > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$senzaCosto ingredienti senza costo: il totale è sottostimato',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.accentDark),
                    ),
                  ],
                  if (r['composizione_variabile'] == true) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'composizione variabile: il costo è una media',
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              children: [
                Text(incidenza == null ? '—' : '${numeroIt(incidenza)}%',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: colore)),
                const Text('incidenza',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DaCollegare extends ConsumerWidget {
  const _DaCollegare();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(daCollegareProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (righe) => righe.isEmpty
                ? const _Vuoto(
                    'Tutto quello che è passato in cassa ha una ricetta.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: righe.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = righe[i];
                      return Card(
                        child: ListTile(
                          title: Text(r['descrizione'] as String? ?? ''),
                          subtitle: Text(
                            '${r['motivo']} · venduto '
                            '${(r['volte_venduto'] as num?)?.toInt() ?? 0} volte',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          trailing: Text(
                            numeroIt(r['pezzi'] as num? ?? 0),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.rigaProposta),
                          ),
                        ),
                      );
                    },
                  ),
          );
}

class _Vuoto extends StatelessWidget {
  final String testo;
  const _Vuoto(this.testo);

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
