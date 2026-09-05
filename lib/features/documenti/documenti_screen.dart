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

class DocumentiScreen extends ConsumerWidget {
  const DocumentiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessione = ref.watch(sessioneProvider);
    final documenti = ref.watch(documentiProvider);

    return Scaffold(
      drawer: const AppDrawer(attiva: '/documenti'),
      appBar: AppBar(
        title: const Text('Documenti'),
        actions: [
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
                  padding:
                      const EdgeInsets.only(bottom: 8, left: 16, right: 16),
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
      floatingActionButton: FloatingActionButton.extended(
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
                padding: const EdgeInsets.all(16),
                itemCount: righe.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _RigaDocumento(righe[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RigaDocumento extends ConsumerWidget {
  final Map<String, dynamic> d;
  const _RigaDocumento(this.d);

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
  Widget build(BuildContext context, WidgetRef ref) {
    final stato = d['stato'] as String? ?? 'bozza';
    final (colore, sfondo, etichetta) =
        _stati[stato] ?? (AppColors.badgeGrey, AppColors.cardLight, stato);

    // Si cancella solo ciò che non ha ancora mosso il magazzino. Un carico
    // confermato si storna dal suo dettaglio, e la storia resta.
    final eliminabile = (stato == 'bozza' || stato == 'in_revisione') &&
        (ref.watch(sessioneProvider).valueOrNull?.puoConfermare ?? false);

    final fornitore = d['fornitore'] as String?;
    final daAgganciare = d['fornitore_da_agganciare'] == true;
    final righe = (d['righe'] as num?)?.toInt() ?? 0;
    final daRisolvere = (d['da_risolvere'] as num?)?.toInt() ?? 0;
    final daConfermare = (d['da_confermare'] as num?)?.toInt() ?? 0;
    final anteprima = d['anteprima'] as String?;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.go('/documenti/${d['id']}'),
      // Tenere premuto per eliminare: la scorciatoia serve a ripulire in
      // fretta le bozze venute male, senza aprirle una per una. Chiede
      // comunque conferma, perché è un gesto che non si annulla.
      onLongPress: eliminabile ? () => _elimina(context, ref, d) : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            // Il nome viene dalla lettura, non dall'anagrafica:
                            // il documento e' comunque riconoscibile, ma resta
                            // un passo da fare.
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
                        // L'imponibile e' il numero che conta per il magazzino;
                        // se manca si mostra il totale documento, che e' quello
                        // stampato in fondo alla carta.
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

              // Cosa c'e' dentro. Con sei documenti aperti e nomi simili,
              // e' l'unica cosa che permette di riconoscerli senza aprirli.
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
                  if (eliminabile) ...[
                    const Spacer(),
                    IconButton(
                      tooltip: 'Elimina',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: AppColors.textMuted,
                      onPressed: () => _elimina(context, ref, d),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
                  // Un elenco vuoto farebbe pensare a un guasto. Non lo e':
                  // e' la sicurezza del database che funziona.
                  ? 'La tua utenza esiste ma non e\' ancora abilitata al '
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
