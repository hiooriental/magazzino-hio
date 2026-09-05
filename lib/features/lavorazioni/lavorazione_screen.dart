import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/contenuto_centrato.dart';
import '../../shared/widgets/scegli_ingrediente.dart';
import 'lavorazioni_screen.dart';

final lavorazioneProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) => repo.lavorazione(id));
final inputProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
        (ref, id) => repo.lavorazioneInput(id));
final outputProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
        (ref, id) => repo.lavorazioneOutput(id));

/// Registrare i pesi. È il gesto di trenta secondi da cui dipende tutto il
/// resto: senza pesi veri, le rese sono numeri copiati da un manuale.
class LavorazioneScreen extends ConsumerWidget {
  final String id;
  const LavorazioneScreen({super.key, required this.id});

  void _ricarica(WidgetRef ref) {
    ref.invalidate(lavorazioneProvider(id));
    ref.invalidate(inputProvider(id));
    ref.invalidate(outputProvider(id));
    ref.invalidate(lavorazioniProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lav = ref.watch(lavorazioneProvider(id));
    final entrate = ref.watch(inputProvider(id)).valueOrNull ?? const [];
    final uscite = ref.watch(outputProvider(id)).valueOrNull ?? const [];
    final puo = ref.watch(sessioneProvider).valueOrNull?.puoConfermare ?? false;

    return lav.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (l) {
        final aperta = l['stato'] == 'aperta';
        final disassemblaggio = l['tipo'] == 'disassemblaggio';

        final pesoIn =
            entrate.fold<num>(0, (s, r) => s + (r['quantita'] as num? ?? 0));
        final pesoOut =
            uscite.fold<num>(0, (s, r) => s + (r['quantita'] as num? ?? 0));
        final resa = pesoIn > 0 ? 100 * pesoOut / pesoIn : null;

        return Scaffold(
          appBar: AppBar(
            title: Text(disassemblaggio ? 'Disassemblaggio' : 'Produzione'),
          ),
          body: ContenutoCentrato(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (!aperta)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _Esito(
                        stato: l['stato'] as String,
                        resa: resa,
                        pesoIn: pesoIn,
                        pesoOut: pesoOut),
                  ),
                _Blocco(
                  titolo: disassemblaggio ? 'Pezzo lavorato' : 'Ingredienti',
                  sottotitolo: disassemblaggio
                      ? 'Il peso messo sulla bilancia prima di tagliare'
                      : 'Quello che è entrato davvero, non quello che dice la ricetta',
                  righe: entrate,
                  modificabile: aperta,
                  onAggiungi: () => _aggiungiInput(context, ref),
                  onTogli: (r) async {
                    await repo.togliRiga(
                        'lavorazione_input', r['id'] as String);
                    _ricarica(ref);
                  },
                  costruisci: (r) => _RigaPeso(
                    nome: (r['ingrediente'] as Map?)?['nome'] as String? ?? '',
                    um: (r['ingrediente'] as Map?)?['um_base'] as String? ?? '',
                    quantita: r['quantita'] as num?,
                  ),
                ),
                const SizedBox(height: 16),
                _Blocco(
                  titolo: disassemblaggio ? 'Tagli ottenuti' : 'Prodotto',
                  sottotitolo: disassemblaggio
                      ? 'Lo scarto non si registra: è la differenza, e il suo '
                          'costo si spalma sui tagli buoni'
                      : 'Quanto ne è uscito: il peso può essere maggiore, '
                          'il riso assorbe acqua',
                  righe: uscite,
                  modificabile: aperta,
                  onAggiungi: () =>
                      _aggiungiOutput(context, ref, disassemblaggio),
                  onTogli: (r) async {
                    await repo.togliRiga(
                        'lavorazione_output', r['id'] as String);
                    _ricarica(ref);
                  },
                  costruisci: (r) => _RigaPeso(
                    nome: (r['ingrediente'] as Map?)?['nome'] as String? ?? '',
                    um: (r['ingrediente'] as Map?)?['um_base'] as String? ?? '',
                    quantita: r['quantita'] as num?,
                    valoreRelativo:
                        disassemblaggio ? r['valore_relativo'] as num? : null,
                    costo: r['costo_unitario'] as num?,
                  ),
                ),
                if (aperta && pesoIn > 0 && pesoOut > 0) ...[
                  const SizedBox(height: 16),
                  _Anteprima(
                      pesoIn: pesoIn,
                      pesoOut: pesoOut,
                      disassemblaggio: disassemblaggio),
                ],
              ],
            ),
          ),
          bottomNavigationBar: !aperta
              ? null
              : Material(
                  elevation: 8,
                  color: AppColors.surface,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!puo)
                            const Text(
                              'Solo titolare o gestore possono chiudere una lavorazione.',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: (puo &&
                                      entrate.isNotEmpty &&
                                      uscite.isNotEmpty)
                                  ? () => _chiudi(context, ref)
                                  : null,
                              icon: const Icon(Icons.check),
                              label: const Text('Chiudi e registra'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _aggiungiInput(BuildContext context, WidgetRef ref) async {
    final ing = await scegliIngrediente(context, titolo: 'Cosa hai lavorato?');
    if (ing == null || !context.mounted) return;
    final q = await chiediNumero(
      context,
      titolo: ing['nome'] as String,
      etichetta: 'Peso in ${ing['um_base']}',
      aiuto: 'Il peso vero sulla bilancia',
    );
    if (q == null || q <= 0) return;

    // Da quale pezzo si sta tagliando. Senza questa domanda i tranci non
    // ricordano da quale tonno vengono, e la catena si spezza proprio dove
    // serve di più.
    String? lotto;
    if (context.mounted) {
      lotto = await scegliLotto(
          context, ing['id'] as String, ing['nome'] as String);
    }

    await repo.aggiungiInput(id, ing['id'] as String, q, lottoId: lotto);
    _ricarica(ref);
  }

  Future<void> _aggiungiOutput(
      BuildContext context, WidgetRef ref, bool disassemblaggio) async {
    final ing = await scegliIngrediente(context, titolo: 'Cosa hai ottenuto?');
    if (ing == null || !context.mounted) return;
    final q = await chiediNumero(
      context,
      titolo: ing['nome'] as String,
      etichetta: 'Peso in ${ing['um_base']}',
    );
    if (q == null || q <= 0) return;

    num valore = 1;
    if (disassemblaggio && context.mounted) {
      valore = await chiediNumero(
            context,
            titolo: 'Quanto vale questo taglio?',
            etichetta: 'Pregio relativo',
            // Non serve un prezzo: contano solo le proporzioni fra i tagli
            // della stessa lavorazione.
            aiuto: 'Rispetto agli altri tagli: filetto 3, tartare 2, ritagli 1',
            iniziale: 1,
          ) ??
          1;
    }
    await repo.aggiungiOutput(id, ing['id'] as String, q, valore);
    _ricarica(ref);
  }

  Future<void> _chiudi(BuildContext context, WidgetRef ref) async {
    try {
      final esito = await repo.chiudiLavorazione(id);
      _ricarica(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.accentGreen,
        content: Text('Resa ${esito['resa_percentuale']}% · '
            '${euro(esito['costo_lavorato'] as num?)} lavorati'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.accent));
    }
  }
}

class _Blocco extends StatelessWidget {
  final String titolo;
  final String sottotitolo;
  final List<Map<String, dynamic>> righe;
  final bool modificabile;
  final VoidCallback onAggiungi;
  final Future<void> Function(Map<String, dynamic>) onTogli;
  final Widget Function(Map<String, dynamic>) costruisci;

  const _Blocco({
    required this.titolo,
    required this.sottotitolo,
    required this.righe,
    required this.modificabile,
    required this.onAggiungi,
    required this.onTogli,
    required this.costruisci,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titolo, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(sottotitolo,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 10),
              if (righe.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Niente ancora',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                ...righe.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: costruisci(r)),
                          if (modificabile)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              color: AppColors.textMuted,
                              onPressed: () => onTogli(r),
                            ),
                        ],
                      ),
                    )),
              if (modificabile) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onAggiungi,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Aggiungi'),
                ),
              ],
            ],
          ),
        ),
      );
}

class _RigaPeso extends StatelessWidget {
  final String nome;
  final String um;
  final num? quantita;
  final num? valoreRelativo;
  final num? costo;

  const _RigaPeso({
    required this.nome,
    required this.um,
    required this.quantita,
    this.valoreRelativo,
    this.costo,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(nome, style: const TextStyle(fontSize: 14))),
              Text(quantitaLeggibile(quantita, um),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          if (valoreRelativo != null || costo != null)
            Text(
              [
                if (valoreRelativo != null)
                  'pregio ${numeroIt(valoreRelativo!)}',
                if (costo != null) 'costo ${numeroIt(costo! * 1000)} €/kg',
              ].join(' · '),
              style:
                  const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
        ],
      );
}

/// Cosa succederà alla chiusura, prima di premere.
class _Anteprima extends StatelessWidget {
  final num pesoIn;
  final num pesoOut;
  final bool disassemblaggio;

  const _Anteprima({
    required this.pesoIn,
    required this.pesoOut,
    required this.disassemblaggio,
  });

  @override
  Widget build(BuildContext context) {
    final resa = 100 * pesoOut / pesoIn;
    final troppo = disassemblaggio && pesoOut > pesoIn;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: troppo ? AppColors.accentLight : AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              troppo
                  // Da otto chili non ne escono dieci: è un errore di
                  // battitura, e la chiusura lo rifiuterà.
                  ? 'Dai tagli esce più di quanto è entrato: controlla i pesi.'
                  : 'Resa ${numeroIt(resa.roundToDouble() == resa ? resa : num.parse(resa.toStringAsFixed(1)))}% · '
                      'scarto ${numeroIt(pesoIn - pesoOut)} g',
              style: TextStyle(
                fontSize: 13,
                color: troppo ? AppColors.accentDark : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Esito extends StatelessWidget {
  final String stato;
  final num? resa;
  final num pesoIn;
  final num pesoOut;

  const _Esito({
    required this.stato,
    required this.resa,
    required this.pesoIn,
    required this.pesoOut,
  });

  @override
  Widget build(BuildContext context) {
    final annullata = stato == 'annullata';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            annullata ? AppColors.accentLight : AppColors.statoConfermatoSfondo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(annullata ? Icons.undo : Icons.check_circle_outline,
              color: annullata ? AppColors.accent : AppColors.statoConfermato),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              annullata
                  ? 'Lavorazione stornata: i movimenti contrari sono stati scritti.'
                  : 'Registrata. Resa ${resa == null ? '—' : numeroIt(num.parse(resa!.toStringAsFixed(1)))}%, '
                      'scarto ${numeroIt(pesoIn - pesoOut)} g.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
