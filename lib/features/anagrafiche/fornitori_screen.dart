import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';
import 'fornitore_sheet.dart';

final fornitoriProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, soloAttivi) async {
  await ref.watch(sessioneProvider.future);
  return repo.fornitori(soloAttivi: soloAttivi);
});

/// I fornitori, con quanti documenti e quanti articoli hanno portato.
///
/// Quei due numeri distinguono un fornitore vero da uno entrato per sbaglio,
/// e dicono anche quanto il sistema ha già imparato su di lui: più articoli
/// abbinati, meno domande alla prossima fattura.
class FornitoriScreen extends ConsumerStatefulWidget {
  const FornitoriScreen({super.key});

  @override
  ConsumerState<FornitoriScreen> createState() => _FornitoriScreenState();
}

class _FornitoriScreenState extends ConsumerState<FornitoriScreen> {
  final _cerca = TextEditingController();
  bool _ancheSpenti = false;

  @override
  void dispose() {
    _cerca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessione = ref.watch(sessioneProvider).valueOrNull;
    final elenco = ref.watch(fornitoriProvider(!_ancheSpenti));

    Future<void> apri([Map<String, dynamic>? f]) async {
      if (sessione == null) return;
      final cambiato = await apriFornitore(
        context,
        fornitore: f,
        organizzazioneId: sessione.organizzazioneId,
      );
      if (cambiato) ref.invalidate(fornitoriProvider);
    }

    return Scaffold(
      drawer: const AppDrawer(attiva: '/fornitori'),
      appBar: AppBar(
        title: const Text('Fornitori'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(fornitoriProvider),
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
                      hintText: 'Cerca per nome o partita IVA',
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      label: const Text('Anche spenti'),
                      selected: _ancheSpenti,
                      onSelected: (v) => setState(() => _ancheSpenti = v),
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
                  final righe = tutti.where((f) {
                    if (q.isEmpty) return true;
                    final n =
                        (f['denominazione'] as String? ?? '').toLowerCase();
                    final p = (f['partita_iva'] as String? ?? '');
                    return n.contains(q) || p.contains(q);
                  }).toList();

                  if (tutti.isEmpty) {
                    return const _Messaggio(
                        'Nessun fornitore.\n\nSi creano qui, oppure nascono da '
                        'soli confermando il fornitore letto su una fattura.');
                  }
                  if (righe.isEmpty) {
                    return const _Messaggio('Nessun risultato.');
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: righe.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _Riga(f: righe[i], onTap: () => apri(righe[i])),
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

int _conta(dynamic v) {
  if (v is List && v.isNotEmpty && v.first is Map) {
    return (v.first['count'] as num?)?.toInt() ?? 0;
  }
  if (v is Map) return (v['count'] as num?)?.toInt() ?? 0;
  return 0;
}

class _Riga extends StatelessWidget {
  final Map<String, dynamic> f;
  final VoidCallback onTap;
  const _Riga({required this.f, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final spento = f['attivo'] == false;
    final documenti = _conta(f['documento_carico']);
    final articoli = _conta(f['articolo_fornitore']);
    final giorni = (f['giorni_consegna'] as List?)?.cast<String>() ?? const [];

    return Opacity(
      opacity: spento ? 0.5 : 1,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f['denominazione'] as String? ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (spento)
                      const Text('spento',
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (f['partita_iva'] != null) 'P.IVA ${f['partita_iva']}',
                    if (f['referente'] != null) f['referente'] as String,
                    if (f['telefono'] != null) f['telefono'] as String,
                  ].join(' · '),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5),
                ),
                if (giorni.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'consegna: ${giorni.map((g) => g.substring(0, 3)).join(', ')}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Pastiglia(documenti == 1
                        ? '1 documento'
                        : '$documenti documenti'),
                    const SizedBox(width: 6),
                    // Quanti articoli suoi il sistema ha già imparato a
                    // riconoscere: più sono, meno domande alla prossima
                    // fattura.
                    _Pastiglia(
                        articoli == 1 ? '1 articolo' : '$articoli articoli'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pastiglia extends StatelessWidget {
  final String testo;
  const _Pastiglia(this.testo);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(testo,
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary)),
      );
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
