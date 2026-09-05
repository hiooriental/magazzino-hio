import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';

final lavorazioniProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);
  return repo.lavorazioni();
});

/// Le lavorazioni, con la resa in evidenza.
///
/// La resa è la colonna che si guarda: dice quanto di quello che hai pagato
/// è finito nel piatto. Sotto il 60% su un pesce c'è qualcosa da chiedere al
/// fornitore o da rivedere al banco.
class LavorazioniScreen extends ConsumerWidget {
  const LavorazioniScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elenco = ref.watch(lavorazioniProvider);
    final sessione = ref.watch(sessioneProvider).valueOrNull;

    return Scaffold(
      drawer: const AppDrawer(attiva: '/lavorazioni'),
      appBar: AppBar(
        title: const Text('Lavorazioni'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(lavorazioniProvider),
          ),
        ],
      ),
      floatingActionButton: sessione == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _nuova(context, ref, sessione),
              icon: const Icon(Icons.add),
              label: const Text('Nuova'),
            ),
      body: elenco.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (righe) => righe.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Nessuna lavorazione.\n\nQui si registrano le preparazioni '
                    'in batch (riso, salse, brodi) e i tagli dei pezzi interi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            : ContenutoCentrato(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: righe.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _Riga(righe[i]),
                ),
              ),
      ),
    );
  }

  Future<void> _nuova(
      BuildContext context, WidgetRef ref, Sessione sessione) async {
    final tipo = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Che lavorazione è?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'produzione'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.blender_outlined, color: AppColors.accent),
              title: Text('Produzione'),
              subtitle: Text('Più ingredienti, un prodotto.\n'
                  'Riso condito, salse, brodi.'),
              isThreeLine: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'disassemblaggio'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.content_cut, color: AppColors.accent),
              title: Text('Disassemblaggio'),
              subtitle: Text('Un pezzo intero, più tagli.\n'
                  'Un loin di tonno, una carcassa.'),
              isThreeLine: true,
            ),
          ),
        ],
      ),
    );
    if (tipo == null || !context.mounted) return;

    final id = await repo.creaLavorazione(
      organizzazioneId: sessione.organizzazioneId,
      tipo: tipo,
    );
    ref.invalidate(lavorazioniProvider);
    if (context.mounted) context.go('/lavorazioni/$id');
  }
}

class _Riga extends StatelessWidget {
  final Map<String, dynamic> l;
  const _Riga(this.l);

  @override
  Widget build(BuildContext context) {
    final stato = l['stato'] as String? ?? '';
    final resa = l['resa_percentuale'] as num?;
    final disassemblaggio = l['tipo'] == 'disassemblaggio';

    // Sotto il 60% qualcosa non va; sopra l'80% su un pesce è un buon taglio.
    final coloreResa = resa == null
        ? AppColors.textMuted
        : resa < 60
            ? AppColors.accent
            : resa < 75
                ? AppColors.inScadenza
                : AppColors.statoConfermato;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/lavorazioni/${l['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(disassemblaggio ? Icons.content_cut : Icons.blender_outlined,
                  color: AppColors.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l['lavorato'] as String? ?? 'Da compilare',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        dataIt(DateTime.tryParse(
                            l['data_lavorazione'] as String? ?? '')),
                        if (l['peso_entrato'] != null)
                          '${numeroIt(l['peso_entrato'] as num)} g in',
                        if (l['peso_uscito'] != null)
                          '${numeroIt(l['peso_uscito'] as num)} g out',
                        if (stato == 'aperta') 'da chiudere',
                        if (stato == 'annullata') 'annullata',
                      ].join(' · '),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (resa != null && stato == 'chiusa')
                Column(
                  children: [
                    Text('${numeroIt(resa)}%',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: coloreResa)),
                    const Text('resa',
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.textSecondary)),
                  ],
                )
              else if (stato == 'aperta')
                const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.rigaProposta),
            ],
          ),
        ),
      ),
    );
  }
}
