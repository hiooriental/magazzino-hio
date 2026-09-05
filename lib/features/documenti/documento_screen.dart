import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/contenuto_centrato.dart';
import 'abbina_sheet.dart';
import 'documenti_screen.dart';

final documentoProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) => repo.documento(id));

final righeProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) => repo.righe(id));

/// La revisione di un documento: dove si guarda solo ciò che serve guardare.
///
/// Le righe già risolte stanno in fondo e in grigio. In cima ci sono quelle
/// che chiedono qualcosa. È l'inverso di come si ordina di solito un elenco,
/// ed è il punto: il valore del sistema si misura in quante righe NON devi
/// guardare.
class DocumentoScreen extends ConsumerWidget {
  final String documentoId;
  const DocumentoScreen({super.key, required this.documentoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documento = ref.watch(documentoProvider(documentoId));
    final righe = ref.watch(righeProvider(documentoId));
    final sessione = ref.watch(sessioneProvider).valueOrNull;

    void ricarica() {
      ref.invalidate(documentoProvider(documentoId));
      ref.invalidate(righeProvider(documentoId));
      ref.invalidate(documentiProvider);
    }

    final doc = documento.valueOrNull;
    final stato = doc?['stato'] as String?;
    final puoAgire = sessione?.puoConfermare ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc?['numero_documento'] as String? ?? 'Documento'),
        actions: [
          if (doc != null && puoAgire)
            PopupMenuButton<String>(
              onSelected: (scelta) async {
                if (scelta == 'elimina') {
                  await _elimina(context, ref, doc);
                } else if (scelta == 'storna') {
                  await _storna(context, ref, doc);
                }
              },
              itemBuilder: (_) => [
                // Una bozza si cancella, un carico confermato si storna.
                // Sono due gesti diversi e non vanno confusi: il primo
                // cancella qualcosa che non è mai successo, il secondo
                // registra che è successo e poi è stato corretto.
                if (stato == 'bozza' || stato == 'in_revisione')
                  const PopupMenuItem(
                    value: 'elimina',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          Icon(Icons.delete_outline, color: AppColors.accent),
                      title: Text('Elimina documento'),
                      subtitle: Text('Non ha ancora mosso il magazzino',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                if (stato == 'confermato')
                  const PopupMenuItem(
                    value: 'storna',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.undo, color: AppColors.accent),
                      title: Text('Storna il carico'),
                      subtitle: Text('Scrive i movimenti contrari',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: documento.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$e', textAlign: TextAlign.center),
        )),
        data: (doc) => righe.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (elenco) => _Corpo(
            documento: doc,
            righe: elenco,
            sessione: sessione,
            onRicarica: ricarica,
          ),
        ),
      ),
    );
  }
}

/// Conferma prima di un gesto che non si annulla.
Future<bool> _sicuro(
  BuildContext context, {
  required String titolo,
  required String testo,
  required String azione,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titolo),
        content: Text(testo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: Text(azione),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _elimina(
    BuildContext context, WidgetRef ref, Map<String, dynamic> doc) async {
  final ok = await _sicuro(
    context,
    titolo: 'Eliminare il documento?',
    testo: 'Spariscono le righe e le foto. Il magazzino non è stato toccato, '
        'quindi non resta traccia di niente.',
    azione: 'Elimina',
  );
  if (!ok || !context.mounted) return;

  try {
    await repo.elimina(doc['id'] as String);
    ref.invalidate(documentiProvider);
    if (context.mounted) context.go('/documenti');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.accent));
    }
  }
}

Future<void> _storna(
    BuildContext context, WidgetRef ref, Map<String, dynamic> doc) async {
  final ok = await _sicuro(
    context,
    titolo: 'Stornare il carico?',
    testo: 'Vengono scritti i movimenti contrari: la merce esce dal magazzino. '
        'Il documento resta in archivio come prova di ciò che è successo.',
    azione: 'Storna',
  );
  if (!ok || !context.mounted) return;

  try {
    final esito = await repo.storna(doc['id'] as String, null);
    ref.invalidate(documentoProvider(doc['id'] as String));
    ref.invalidate(righeProvider(doc['id'] as String));
    ref.invalidate(documentiProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${esito['movimenti_stornati']} movimenti stornati. '
            '${esito['nota']}'),
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.accent));
    }
  }
}

class _Corpo extends StatelessWidget {
  final Map<String, dynamic> documento;
  final List<Map<String, dynamic>> righe;
  final Sessione? sessione;
  final VoidCallback onRicarica;

  const _Corpo({
    required this.documento,
    required this.righe,
    required this.sessione,
    required this.onRicarica,
  });

  int get _daRisolvere =>
      righe.where((r) => r['stato_match'] == 'da_risolvere').length;
  int get _daConfermare =>
      righe.where((r) => r['stato_match'] == 'suggerito').length;
  int get _automatiche =>
      righe.where((r) => r['stato_match'] == 'confermato').length;

  bool get _confermato => documento['stato'] == 'confermato';

  @override
  Widget build(BuildContext context) {
    // Le righe che chiedono attenzione per prime: da risolvere, poi da
    // confermare, poi quelle a posto.
    const ordine = {
      'da_risolvere': 0,
      'suggerito': 1,
      'confermato': 2,
      'ignorata': 3
    };
    final ordinate = [...righe]..sort((a, b) {
        final da = ordine[a['stato_match']] ?? 9;
        final db = ordine[b['stato_match']] ?? 9;
        if (da != db) return da.compareTo(db);
        return (a['numero_riga'] as int).compareTo(b['numero_riga'] as int);
      });

    return Column(
      children: [
        Expanded(
          child: ContenutoCentrato(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Testata(documento: documento, onRicarica: onRicarica),
                const SizedBox(height: 12),
                _Riepilogo(
                  automatiche: _automatiche,
                  daConfermare: _daConfermare,
                  daRisolvere: _daRisolvere,
                ),
                const SizedBox(height: 16),
                ...ordinate.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _Riga(
                        riga: r,
                        modificabile: !_confermato,
                        fornitoreIndicato: documento['fornitore'] != null,
                        onRicarica: onRicarica,
                      ),
                    )),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        if (!_confermato && documento['stato'] != 'annullato')
          _BarraConferma(
            documento: documento,
            daRisolvere: _daRisolvere,
            sessione: sessione,
            onRicarica: onRicarica,
          ),
      ],
    );
  }
}

class _Testata extends StatelessWidget {
  final Map<String, dynamic> documento;
  final VoidCallback onRicarica;
  const _Testata({required this.documento, required this.onRicarica});

  @override
  Widget build(BuildContext context) {
    final fornitore = documento['fornitore'] as Map?;
    final imponibile = documento['totale_dichiarato'] as num?;
    final calcolato = documento['totale_calcolato'] as num?;
    final scostamento = (imponibile != null && calcolato != null)
        ? calcolato - imponibile
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fornitore == null)
              // Senza fornitore non si può abbinare niente: gli articoli
              // appartengono a un fornitore, non al documento.
              _AvvisoFornitore(
                documentoId: documento['id'] as String,
                nomeLetto: documento['fornitore_letto'] as String?,
                onFatto: onRicarica,
              )
            else
              Text(fornitore['denominazione'] as String,
                  style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              [
                (documento['tipo'] as String? ?? '').toUpperCase(),
                if (documento['numero_documento'] != null)
                  'n. ${documento['numero_documento']}',
                dataIt(DateTime.tryParse(
                    documento['data_consegna'] as String? ?? '')),
              ].join(' · '),
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const Divider(height: 24),
            _Voce('Imponibile letto', euro(imponibile)),
            _Voce('Totale documento',
                euro(documento['totale_documento'] as num?)),
            if (calcolato != null) _Voce('Somma delle righe', euro(calcolato)),
            if (scostamento != null && scostamento.abs() > 0.01) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                // Se la somma delle righe non fa l'imponibile, o manca una
                // riga o un numero è stato letto male. Vale la pena guardare
                // prima di far entrare la merce.
                child: Text(
                  'Le righe non fanno l\'imponibile: differenza di '
                  '${euro(scostamento.abs())}.',
                  style: const TextStyle(
                      color: AppColors.accentDark, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvvisoFornitore extends StatefulWidget {
  final String documentoId;
  final String? nomeLetto;
  final VoidCallback onFatto;
  const _AvvisoFornitore({
    required this.documentoId,
    required this.nomeLetto,
    required this.onFatto,
  });

  @override
  State<_AvvisoFornitore> createState() => _AvvisoFornitoreState();
}

class _AvvisoFornitoreState extends State<_AvvisoFornitore> {
  bool _inCorso = false;

  Future<void> _crea() async {
    setState(() => _inCorso = true);
    try {
      final esito = await repo.creaFornitore(widget.documentoId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(esito['creato'] == true
            ? 'Fornitore creato: ${esito['denominazione']}'
            : 'Agganciato a ${esito['denominazione']}'),
      ));
      widget.onFatto();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final letto = widget.nomeLetto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Il nome letto sul documento si mostra comunque, in grande: e' il
        // fornitore, anche se in anagrafica non c'e' ancora. Nasconderlo
        // dietro un "da indicare" farebbe sembrare che il sistema non
        // l'abbia riconosciuto.
        Text(
          letto ?? 'Fornitore da indicare',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          letto == null
              ? 'Sul documento non si legge chi lo ha emesso: va scelto a mano.'
              : 'Non è ancora in anagrafica. Gli articoli appartengono a un '
                  'fornitore: senza, non si può abbinare nulla.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _inCorso ? null : _crea,
          icon: const Icon(Icons.add_business_outlined, size: 18),
          label: Text(letto == null
              ? 'Crea da quanto letto'
              : 'Aggiungi in anagrafica'),
        ),
      ],
    );
  }
}

class _Voce extends StatelessWidget {
  final String etichetta;
  final String valore;
  const _Voce(this.etichetta, this.valore);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etichetta,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            Text(valore,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}

class _Riepilogo extends StatelessWidget {
  final int automatiche, daConfermare, daRisolvere;
  const _Riepilogo({
    required this.automatiche,
    required this.daConfermare,
    required this.daRisolvere,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Pastiglia(
              numero: automatiche,
              testo: 'automatiche',
              colore: AppColors.rigaAutomatica),
          const SizedBox(width: 8),
          _Pastiglia(
              numero: daConfermare,
              testo: 'da confermare',
              colore: AppColors.rigaProposta),
          const SizedBox(width: 8),
          _Pastiglia(
              numero: daRisolvere,
              testo: 'da abbinare',
              colore: AppColors.rigaDaRisolvere),
        ],
      );
}

class _Pastiglia extends StatelessWidget {
  final int numero;
  final String testo;
  final Color colore;
  const _Pastiglia(
      {required this.numero, required this.testo, required this.colore});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: numero == 0
                ? AppColors.cardLight
                : colore.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text('$numero',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: numero == 0 ? AppColors.textMuted : colore,
                  )),
              Text(testo,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}

class _Riga extends StatelessWidget {
  final Map<String, dynamic> riga;
  final bool modificabile;
  final bool fornitoreIndicato;
  final VoidCallback onRicarica;

  const _Riga({
    required this.riga,
    required this.modificabile,
    required this.fornitoreIndicato,
    required this.onRicarica,
  });

  @override
  Widget build(BuildContext context) {
    final stato = riga['stato_match'] as String?;
    final colore = switch (stato) {
      'confermato' => AppColors.rigaAutomatica,
      'suggerito' => AppColors.rigaProposta,
      _ => AppColors.rigaDaRisolvere,
    };
    final ingrediente = (riga['ingrediente'] as Map?)?['nome'] as String?;
    final um = (riga['ingrediente'] as Map?)?['um_base'] as String? ?? '';
    final quantita = riga['quantita_base'] as num?;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: !modificabile
          ? null
          : () async {
              // Gli articoli appartengono a un fornitore. Senza, `abbina_riga`
              // rifiuterebbe — ma solo dopo che l'operatore ha compilato tutto
              // il modulo. Meglio dirlo prima.
              if (!fornitoreIndicato) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Prima indica il fornitore del documento.'),
                ));
                return;
              }
              final esito = await showModalBottomSheet<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AbbinaSheet(riga: riga),
              );
              if (esito != null) onRicarica();
            },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(
                  color: colore,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Due righe al massimo: certi fornitori infilano nella
                    // descrizione misure, riferimenti d'ordine e codici
                    // interni, e tre schede identiche alte mezzo schermo
                    // rendono impossibile scorrere il documento. Il testo
                    // completo resta nel pannello di abbinamento.
                    Text(
                      riga['descrizione_originale'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // Ciò che c'era scritto: è quello che l'operatore
                      // confronta con la carta.
                      [
                        if (riga['quantita_testo'] != null)
                          '${riga['quantita_testo']} ${riga['um_dichiarata'] ?? ''}',
                        if (riga['prezzo_testo'] != null)
                          '× ${riga['prezzo_testo']}',
                        if (riga['totale_testo'] != null)
                          '= ${riga['totale_testo']}',
                      ].join(' '),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    if (ingrediente != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.arrow_forward, size: 14, color: colore),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              quantita != null
                                  // "1.200 kg", non "1200000 g": nessuno legge
                                  // i grammi a sei cifre, e sul documento
                                  // c'era scritto proprio in chili.
                                  ? '$ingrediente · ${quantitaLeggibile(quantita, um)}'
                                  : ingrediente,
                              style: TextStyle(color: colore, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ] else if (modificabile) ...[
                      const SizedBox(height: 6),
                      Text('Da abbinare — tocca per farlo',
                          style: TextStyle(color: colore, fontSize: 13)),
                    ],
                    if (riga['note'] != null) ...[
                      const SizedBox(height: 6),
                      Text(riga['note'] as String,
                          style: const TextStyle(
                              color: AppColors.accentDark, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarraConferma extends StatefulWidget {
  final Map<String, dynamic> documento;
  final int daRisolvere;
  final Sessione? sessione;
  final VoidCallback onRicarica;

  const _BarraConferma({
    required this.documento,
    required this.daRisolvere,
    required this.sessione,
    required this.onRicarica,
  });

  @override
  State<_BarraConferma> createState() => _BarraConfermaState();
}

class _BarraConfermaState extends State<_BarraConferma> {
  bool _inCorso = false;

  Future<void> _conferma() async {
    setState(() => _inCorso = true);
    try {
      final esito = await repo.conferma(widget.documento['id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.accentGreen,
        content: Text('Caricate ${esito['righe_caricate']} righe '
            'per ${euro(esito['valore_caricato'] as num?)}.'),
      ));
      widget.onRicarica();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.accent));
      setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final puo = widget.sessione?.puoConfermare ?? false;
    final pronto = widget.daRisolvere == 0;

    return Material(
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
                  'Solo titolare o gestore possono confermare un carico.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13),
                )
              else if (!pronto)
                Text(
                  widget.daRisolvere == 1
                      ? 'Una riga da sistemare prima di confermare.'
                      : '${widget.daRisolvere} righe da sistemare prima di confermare.',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              if (!puo || !pronto) const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (puo && pronto && !_inCorso) ? _conferma : null,
                  icon: const Icon(Icons.check),
                  label: Text(_inCorso
                      ? 'Sto caricando…'
                      : 'Conferma e carica in magazzino'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
