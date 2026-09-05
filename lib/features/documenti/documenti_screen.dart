import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db.dart';
import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';

/// I documenti di carico, dal piu' recente.
///
/// Legge dalla vista `documento_riepilogo` invece che dalla tabella: cosi'
/// ogni riga porta gia' con se' il fornitore, quante righe ha e quante ne
/// restano da sistemare. Leggendo la tabella servirebbe una query per ogni
/// documento solo per contare le sue righe.
final documentiProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);

  return List<Map<String, dynamic>>.from(
    await Db.mag
        .from('documento_riepilogo')
        .select()
        .order('stato')
        .order('data_consegna', ascending: false)
        .limit(60),
  );
});

/// Si cancella solo cio' che non ha ancora mosso il magazzino. Un carico
/// confermato si storna dal suo dettaglio, e la storia resta.
bool _eliminabile(Map<String, dynamic> d, Sessione? s) =>
    (d['stato'] == 'bozza' || d['stato'] == 'in_revisione') &&
    (s?.puoConfermare ?? false);

class DocumentiScreen extends ConsumerStatefulWidget {
  const DocumentiScreen({super.key});

  @override
  ConsumerState<DocumentiScreen> createState() => _DocumentiScreenState();
}

class _DocumentiScreenState extends ConsumerState<DocumentiScreen> {
  /// Gli id scelti. Vuoto significa modalita' normale: la selezione si apre
  /// tenendo premuto su una scheda, come ovunque.
  final _scelti = <String>{};
  bool _inSelezione = false;

  void _esci() => setState(() {
        _inSelezione = false;
        _scelti.clear();
      });

  void _cambia(String id) => setState(() {
        if (!_scelti.remove(id)) _scelti.add(id);
        if (_scelti.isEmpty) _inSelezione = false;
      });

  @override
  Widget build(BuildContext context) {
    final sessione = ref.watch(sessioneProvider);
    final documenti = ref.watch(documentiProvider);
    final elenco = documenti.valueOrNull ?? const <Map<String, dynamic>>[];
    final eliminabili =
        elenco.where((d) => _eliminabile(d, sessione.valueOrNull)).toList();

    return Scaffold(
      drawer: _inSelezione ? null : const AppDrawer(attiva: '/documenti'),
      appBar: _inSelezione
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _esci,
              ),
              title: Text(_scelti.length == 1
                  ? '1 selezionato'
                  : '${_scelti.length} selezionati'),
              actions: [
                if (_scelti.length < eliminabili.length)
                  IconButton(
                    tooltip: 'Seleziona tutti',
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() => _scelti
                      ..clear()
                      ..addAll(eliminabili.map((d) => d['id'] as String))),
                  ),
                IconButton(
                  tooltip: 'Elimina',
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.accent,
                  onPressed:
                      _scelti.isEmpty ? null : () => _eliminaScelti(elenco),
                ),
              ],
            )
          : AppBar(
              title: const Text('Documenti'),
              actions: [
                if (eliminabili.isNotEmpty)
                  IconButton(
                    tooltip: 'Seleziona',
                    icon: const Icon(Icons.checklist),
                    onPressed: () => setState(() => _inSelezione = true),
                  ),
                IconButton(
                  tooltip: 'Aggiorna',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(documentiProvider),
                ),
              ],
              bottom: sessione.hasValue
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(28),
                      child: Padding(
                        padding: const EdgeInsets.only(
                            bottom: 8, left: 16, right: 16),
                        child: Row(
                          children: [
                            Text(
                              '${sessione.value!.organizzazione} · ${sessione.value!.ruolo}',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
      floatingActionButton: _inSelezione
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/documenti/nuovo'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Fotografa'),
            ),
      body: documenti.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Errore(
          errore: e,
          onRiprova: () {
            ref.invalidate(sessioneProvider);
            ref.invalidate(documentiProvider);
          },
        ),
        data: (righe) {
          if (righe.isEmpty) return const _Vuoto();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(documentiProvider),
            child: ContenutoCentrato(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: righe.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final d = righe[i];
                  final id = d['id'] as String;
                  final puo = _eliminabile(d, sessione.valueOrNull);
                  return _RigaDocumento(
                    d: d,
                    eliminabile: puo,
                    inSelezione: _inSelezione,
                    selezionato: _scelti.contains(id),
                    onTap: () {
                      if (_inSelezione) {
                        if (puo) _cambia(id);
                      } else {
                        context.go('/documenti/$id');
                      }
                    },
                    onLongPress: puo
                        ? () => setState(() {
                              _inSelezione = true;
                              _scelti.add(id);
                            })
                        : null,
                    onElimina: () => _elimina(context, ref, d),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _eliminaScelti(List<Map<String, dynamic>> elenco) async {
    final quanti = _scelti.length;
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(quanti == 1
                ? 'Eliminare il documento?'
                : 'Eliminare $quanti documenti?'),
            content: Text(
              'Spariscono le righe e le foto. Il magazzino non è stato '
              'toccato, quindi non resta traccia di niente.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Annulla')),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: const Text('Elimina'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    // Uno alla volta, contando quelli che non passano: se il database ne
    // rifiuta uno — perché nel frattempo è stato confermato da qualcun
    // altro — gli altri devono comunque andare via.
    var fatti = 0;
    final falliti = <String>[];
    for (final id in _scelti.toList()) {
      try {
        await repo.elimina(id);
        fatti++;
      } catch (_) {
        final d = elenco.firstWhere((x) => x['id'] == id, orElse: () => {});
        falliti.add((d['numero_documento'] as String?) ?? 'senza numero');
      }
    }

    _esci();
    ref.invalidate(documentiProvider);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          falliti.isEmpty ? AppColors.accentGreen : AppColors.accent,
      content: Text(falliti.isEmpty
          ? '$fatti ${fatti == 1 ? 'documento eliminato' : 'documenti eliminati'}.'
          : '$fatti eliminati, non riusciti: ${falliti.join(', ')}.'),
    ));
  }
}

Future<void> _elimina(
    BuildContext context, WidgetRef ref, Map<String, dynamic> d) async {
  final nome = (d['fornitore'] as String?) ?? 'questo documento';
  final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Eliminare il documento?'),
          content: Text(
            '$nome, ${d['numero_documento'] ?? 'senza numero'}.\n\n'
            'Spariscono le righe e le foto. Il magazzino non è stato toccato, '
            'quindi non resta traccia di niente.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Annulla')),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              child: const Text('Elimina'),
            ),
          ],
        ),
      ) ??
      false;
  if (!ok) return;

  try {
    await repo.elimina(d['id'] as String);
    ref.invalidate(documentiProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.accent));
    }
  }
}

class _RigaDocumento extends StatelessWidget {
  final Map<String, dynamic> d;
  final bool eliminabile;
  final bool inSelezione;
  final bool selezionato;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onElimina;

  const _RigaDocumento({
    required this.d,
    required this.eliminabile,
    required this.inSelezione,
    required this.selezionato,
    required this.onTap,
    required this.onLongPress,
    required this.onElimina,
  });

  static const _stati = {
    'bozza': (AppColors.statoBozza, AppColors.statoBozzaSfondo, 'Bozza'),
    'in_revisione': (
      AppColors.statoRevisione,
      AppColors.statoRevisioneSfondo,
      'Da rivedere'
    ),
    'confermato': (
      AppColors.statoConfermato,
      AppColors.statoConfermatoSfondo,
      'Confermato'
    ),
    'annullato': (
      AppColors.statoAnnullato,
      AppColors.statoAnnullatoSfondo,
      'Annullato'
    ),
  };

  @override
  Widget build(BuildContext context) {
    final stato = d['stato'] as String? ?? 'bozza';
    final (colore, sfondo, etichetta) =
        _stati[stato] ?? (AppColors.badgeGrey, AppColors.cardLight, stato);

    final fornitore = d['fornitore'] as String?;
    final daAgganciare = d['fornitore_da_agganciare'] == true;
    final righe = (d['righe'] as num?)?.toInt() ?? 0;
    final daRisolvere = (d['da_risolvere'] as num?)?.toInt() ?? 0;
    final daConfermare = (d['da_confermare'] as num?)?.toInt() ?? 0;
    final anteprima = d['anteprima'] as String?;

    return Opacity(
      // In selezione, quello che non si può eliminare si spegne: è più
      // onesto che lasciarlo toccabile senza effetto.
      opacity: (inSelezione && !eliminabile) ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Card(
          color: selezionato ? AppColors.accentLight : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (inSelezione)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          selezionato
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: selezionato
                              ? AppColors.accent
                              : AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  fornitore ?? 'Fornitore sconosciuto',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              // Il nome viene dalla lettura, non
                              // dall'anagrafica: il documento è comunque
                              // riconoscibile, ma resta un passo da fare.
                              if (daAgganciare && fornitore != null) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.help_outline,
                                    size: 15, color: AppColors.goldDark),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              (d['tipo'] as String? ?? '').toUpperCase(),
                              if ((d['numero_documento'] as String?)
                                      ?.isNotEmpty ??
                                  false)
                                'n. ${d['numero_documento']}',
                              dataIt(DateTime.tryParse(
                                  d['data_consegna'] as String? ?? '')),
                            ].join(' · '),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: sfondo,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            etichetta,
                            style: TextStyle(
                              color: colore,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          // L'imponibile è il numero che conta per il
                          // magazzino; se manca si mostra il totale
                          // documento, che è quello stampato sulla carta.
                          euro(d['totale_dichiarato'] as num? ??
                              d['totale_documento'] as num?),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Cosa c'è dentro. Con sei documenti aperti e nomi simili,
                // è l'unica cosa che permette di riconoscerli senza aprirli.
                if (anteprima != null && anteprima.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    anteprima,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12.5),
                  ),
                ],

                const SizedBox(height: 8),
                Row(
                  children: [
                    _Conteggio(
                      testo: righe == 1 ? '1 riga' : '$righe righe',
                      colore: AppColors.textSecondary,
                    ),
                    if (daRisolvere > 0) ...[
                      const SizedBox(width: 6),
                      _Conteggio(
                        testo: '$daRisolvere da abbinare',
                        colore: AppColors.rigaDaRisolvere,
                        evidenzia: true,
                      ),
                    ],
                    if (daConfermare > 0) ...[
                      const SizedBox(width: 6),
                      _Conteggio(
                        testo: '$daConfermare da confermare',
                        colore: AppColors.rigaProposta,
                        evidenzia: true,
                      ),
                    ],
                    if (daAgganciare) ...[
                      const SizedBox(width: 6),
                      const _Conteggio(
                        testo: 'fornitore da creare',
                        colore: AppColors.goldDark,
                        evidenzia: true,
                      ),
                    ],
                    if (eliminabile && !inSelezione) ...[
                      const Spacer(),
                      IconButton(
                        tooltip: 'Elimina',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: AppColors.textMuted,
                        onPressed: onElimina,
                      ),
                    ],
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

class _Conteggio extends StatelessWidget {
  final String testo;
  final Color colore;
  final bool evidenzia;

  const _Conteggio({
    required this.testo,
    required this.colore,
    this.evidenzia = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:
              evidenzia ? colore.withValues(alpha: 0.10) : AppColors.cardLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          testo,
          style: TextStyle(
            fontSize: 11.5,
            color: colore,
            fontWeight: evidenzia ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
}

class _Vuoto extends StatelessWidget {
  const _Vuoto();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text(
                'Nessun documento.\nIl primo carico si crea fotografando un DDT.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
}

class _Errore extends StatelessWidget {
  final Object errore;
  final VoidCallback onRiprova;
  const _Errore({required this.errore, required this.onRiprova});

  @override
  Widget build(BuildContext context) {
    final nonAbilitato = errore is NonAbilitato;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              nonAbilitato
                  // Un elenco vuoto farebbe pensare a un guasto. Non lo è:
                  // è la sicurezza del database che funziona.
                  ? 'La tua utenza esiste ma non è ancora abilitata al '
                      'magazzino. Deve aggiungerti il titolare.'
                  : 'Non riesco a leggere i documenti.\n$errore',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRiprova, child: const Text('Riprova')),
          ],
        ),
      ),
    );
  }
}
