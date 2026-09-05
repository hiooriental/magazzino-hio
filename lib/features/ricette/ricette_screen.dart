import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';

final prodottiProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);
  return repo.prodottiVenduti();
});

final semilavoratiProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);
  return repo.semilavorati();
});

/// Le ricette: piatti a menù e semilavorati.
///
/// In cima quelli SENZA ricetta, perché sono quelli che tengono fermo tutto
/// il resto: finché un piatto non ha una distinta, la sua vendita non scarica
/// niente e il suo food cost non esiste.
class RicetteScreen extends ConsumerStatefulWidget {
  const RicetteScreen({super.key});

  @override
  ConsumerState<RicetteScreen> createState() => _RicetteScreenState();
}

class _RicetteScreenState extends ConsumerState<RicetteScreen> {
  bool _semilavorati = false;

  @override
  Widget build(BuildContext context) {
    final sessione = ref.watch(sessioneProvider).valueOrNull;

    return Scaffold(
      drawer: const AppDrawer(attiva: '/ricette'),
      appBar: AppBar(
        title: const Text('Ricette'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(prodottiProvider);
              ref.invalidate(semilavoratiProvider);
            },
          ),
        ],
      ),
      floatingActionButton: (_semilavorati || sessione == null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _nuovoProdotto(sessione),
              icon: const Icon(Icons.add),
              label: const Text('Nuovo piatto'),
            ),
      body: ContenutoCentrato(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Piatti')),
                  ButtonSegment(value: true, label: Text('Semilavorati')),
                ],
                selected: {_semilavorati},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    setState(() => _semilavorati = s.first),
              ),
            ),
            Expanded(
              child: _semilavorati ? const _Semilavorati() : const _Piatti(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _nuovoProdotto(Sessione sessione) async {
    final nome = TextEditingController();
    final codice = TextEditingController();
    final categoria = TextEditingController();
    final prezzo = TextEditingController();

    final creare = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nuovo piatto'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nome,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: prezzo,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Prezzo di vendita'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoria,
                decoration:
                    const InputDecoration(labelText: 'Categoria a menù'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codice,
                decoration: const InputDecoration(
                  labelText: 'Codice di cassa',
                  // Senza, le vendite non si agganciano da sole e ogni
                  // scontrino chiede un abbinamento a mano.
                  helperText:
                      'Come lo chiama iPratico. Si può aggiungere dopo.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annulla')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Crea')),
        ],
      ),
    );

    if (creare != true || nome.text.trim().isEmpty) return;

    try {
      final id = await repo.creaProdottoVenduto(
        organizzazioneId: sessione.organizzazioneId,
        nome: nome.text.trim(),
        codiceEsterno: codice.text.trim(),
        categoria: categoria.text.trim(),
        prezzo: num.tryParse(prezzo.text.replaceAll(',', '.')),
      );
      final distinta = await repo.distintaAttiva(
        organizzazioneId: sessione.organizzazioneId,
        prodottoVendutoId: id,
      );
      ref.invalidate(prodottiProvider);
      if (mounted) context.go('/ricette/$distinta');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

bool _haRicetta(Map<String, dynamic> r) {
  final d = r['distinta'];
  if (d is List) return d.any((x) => x['stato'] == 'attiva');
  if (d is Map) return d['stato'] == 'attiva';
  return false;
}

String? _idDistinta(Map<String, dynamic> r) {
  final d = r['distinta'];
  if (d is List) {
    for (final x in d) {
      if (x['stato'] == 'attiva') return x['id'] as String;
    }
  }
  if (d is Map && d['stato'] == 'attiva') return d['id'] as String;
  return null;
}

class _Piatti extends ConsumerWidget {
  const _Piatti();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(prodottiProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (righe) {
              if (righe.isEmpty) {
                return const _Vuoto(
                    'Nessun piatto in anagrafica.\n\nSi creano qui, oppure '
                    'arrivano da soli quando si importano le vendite.');
              }
              // Prima quelli senza ricetta: sono il lavoro da fare.
              final ordinati = [...righe]..sort((a, b) {
                  final ha = _haRicetta(a) ? 1 : 0;
                  final hb = _haRicetta(b) ? 1 : 0;
                  if (ha != hb) return ha.compareTo(hb);
                  return (a['nome'] as String).compareTo(b['nome'] as String);
                });
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: ordinati.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _RigaProdotto(ordinati[i]),
              );
            },
          );
}

class _RigaProdotto extends ConsumerWidget {
  final Map<String, dynamic> p;
  const _RigaProdotto(this.p);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ha = _haRicetta(p);
    final senza = p['senza_distinta'] == true;

    return Card(
      child: ListTile(
        title: Text(p['nome'] as String? ?? ''),
        subtitle: Text(
          [
            if (p['categoria_menu'] != null) p['categoria_menu'] as String,
            if (p['prezzo_vendita'] != null) euro(p['prezzo_vendita'] as num?),
            if (p['codice_esterno'] == null) 'senza codice di cassa',
          ].join(' · '),
          style: const TextStyle(fontSize: 12.5),
        ),
        trailing: senza
            ? const Text('non consuma\nmagazzino',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted))
            : Icon(
                ha ? Icons.check_circle_outline : Icons.add_circle_outline,
                color: ha ? AppColors.statoConfermato : AppColors.rigaProposta,
              ),
        onTap: senza
            ? null
            : () async {
                final sessione = ref.read(sessioneProvider).valueOrNull;
                if (sessione == null) return;
                final id = _idDistinta(p) ??
                    await repo.distintaAttiva(
                      organizzazioneId: sessione.organizzazioneId,
                      prodottoVendutoId: p['id'] as String,
                    );
                if (context.mounted) context.go('/ricette/$id');
              },
      ),
    );
  }
}

class _Semilavorati extends ConsumerWidget {
  const _Semilavorati();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(semilavoratiProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (righe) => righe.isEmpty
                ? const _Vuoto(
                    'Nessun semilavorato.\n\nUn semilavorato è un ingrediente '
                    'che si produce invece di comprarlo: riso condito, salse, '
                    'brodi, tranci ricavati da un pezzo intero.\n\n'
                    'Si segna come tale dalla scheda dell\'ingrediente.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: righe.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = righe[i];
                      final ha = _haRicetta(s);
                      return Card(
                        child: ListTile(
                          title: Text(s['nome'] as String? ?? ''),
                          subtitle: Text(
                            s['costo_medio'] == null
                                ? 'in ${s['um_base']} · nessun costo ancora'
                                : 'in ${s['um_base']} · '
                                    '${numeroIt((s['costo_medio'] as num) * 1000)} €/kg',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          trailing: Icon(
                            ha
                                ? Icons.check_circle_outline
                                : Icons.add_circle_outline,
                            color: ha
                                ? AppColors.statoConfermato
                                : AppColors.rigaProposta,
                          ),
                          onTap: () async {
                            final sessione =
                                ref.read(sessioneProvider).valueOrNull;
                            if (sessione == null) return;
                            var id = _idDistinta(s);
                            if (id == null) {
                              // La resa serve a dividere il costo degli
                              // ingredienti sulla quantità prodotta: senza,
                              // il costo unitario non si può calcolare.
                              final resa = await chiediResa(context,
                                  s['nome'] as String, s['um_base'] as String);
                              if (resa == null) return;
                              id = await repo.distintaAttiva(
                                organizzazioneId: sessione.organizzazioneId,
                                ingredienteId: s['id'] as String,
                                quantitaProdotta: resa,
                              );
                            }
                            if (context.mounted) context.go('/ricette/$id');
                          },
                        ),
                      );
                    },
                  ),
          );
}

/// Quanto ne esce da una preparazione intera.
Future<num?> chiediResa(BuildContext context, String nome, String um) async {
  final c = TextEditingController();
  final v = await showDialog<num>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Quanto $nome esce da una preparazione?'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Resa in $um',
          helperText: 'Il peso finito, non la somma degli ingredienti',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, num.tryParse(c.text.replaceAll(',', '.'))),
          child: const Text('Conferma'),
        ),
      ],
    ),
  );
  c.dispose();
  return v;
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
