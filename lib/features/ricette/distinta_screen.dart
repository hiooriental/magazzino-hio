import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sessione.dart';
import '../anagrafiche/ingrediente_sheet.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/contenuto_centrato.dart';
import '../../shared/widgets/scegli_ingrediente.dart';
import 'ricette_screen.dart';

final distintaProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) => repo.distinta(id));
final componentiProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
        (ref, id) => repo.componenti(id));

/// La ricetta di un piatto o di un semilavorato.
///
/// Accanto a ogni ingrediente c'è quanto pesa sul costo del piatto: è il
/// numero che serve quando si cerca dove intervenire. Un elenco di grammi
/// non lo dice.
class DistintaScreen extends ConsumerWidget {
  final String id;
  const DistintaScreen({super.key, required this.id});

  void _ricarica(WidgetRef ref) {
    ref.invalidate(distintaProvider(id));
    ref.invalidate(componentiProvider(id));
    ref.invalidate(prodottiProvider);
    ref.invalidate(semilavoratiProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(distintaProvider(id));
    final componenti =
        ref.watch(componentiProvider(id)).valueOrNull ?? const [];

    return d.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (dist) {
        final perProdotto = dist['prodotto_venduto_id'] != null;
        // Le parentesi servono davvero: dentro un ternario, il `?` di
        // `String?` verrebbe letto come l'inizio di un altro ternario.
        final nome = perProdotto
            ? ((dist['prodotto_venduto'] as Map?)?['nome'] as String? ?? '')
            : ((dist['ingrediente'] as Map?)?['nome'] as String? ?? '');
        final prezzo =
            (dist['prodotto_venduto'] as Map?)?['prezzo_vendita'] as num?;
        final resa = dist['quantita_prodotta'] as num?;
        final umResa =
            (dist['ingrediente'] as Map?)?['um_base'] as String? ?? '';

        // Il costo si ricalcola qui invece di chiederlo al database a ogni
        // modifica: gli ingredienti hanno già il loro costo medio, e sommare
        // in Dart evita un viaggio per ogni tocco.
        num costo = 0;
        var senzaCosto = 0;
        for (final c in componenti) {
          final cm = (c['ingrediente'] as Map?)?['costo_medio'] as num?;
          if (cm == null) {
            senzaCosto++;
            continue;
          }
          final scarto = (c['scarto_percentuale'] as num?) ?? 0;
          costo += (c['quantita'] as num) / (1 - scarto / 100) * cm;
        }
        final costoUnitario =
            (!perProdotto && resa != null && resa > 0) ? costo / resa : null;

        return Scaffold(
          appBar: AppBar(
            title: Text(nome),
            actions: [
              IconButton(
                tooltip: 'Modifica',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    _modificaTestata(context, ref, dist, perProdotto),
              ),
            ],
          ),
          body: ContenutoCentrato(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                _Testata(
                  perProdotto: perProdotto,
                  costo: costo,
                  costoUnitario: costoUnitario,
                  umResa: umResa,
                  prezzo: prezzo,
                  resa: resa,
                  senzaCosto: senzaCosto,
                  onCambiaResa: () async {
                    final r = await chiediResa(context, nome, umResa);
                    if (r == null) return;
                    await repo.impostaResa(id, r);
                    _ricarica(ref);
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ingredienti',
                            style: Theme.of(context).textTheme.titleMedium),

                        // Cosa dice il menù. Serve mentre si compone la
                        // ricetta: evita di andarsela a cercare sul sito e di
                        // dimenticarne metà.
                        if ((dist['prodotto_venduto']
                                as Map?)?['descrizione'] !=
                            null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.goldLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              (dist['prodotto_venduto'] as Map)['descrizione']
                                  as String,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                  height: 1.35),
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),
                        if (componenti.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Nessun ingrediente. Finché la ricetta è vuota, '
                              'vendere questo piatto non scarica niente.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        else
                          ...componenti.map((c) => _Componente(
                                c: c,
                                costoTotale: costo,
                                onModifica: () => _modifica(context, ref, c),
                                onTogli: () async {
                                  await repo.togliRiga(
                                      'distinta_componente', c['id'] as String);
                                  _ricarica(ref);
                                },
                              )),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () => _aggiungi(context, ref),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Aggiungi ingrediente'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _aggiungi(BuildContext context, WidgetRef ref) async {
    final ing = await scegliIngrediente(context, titolo: 'Quale ingrediente?');
    if (ing == null || !context.mounted) return;

    final q = await chiediNumero(
      context,
      titolo: ing['nome'] as String,
      etichetta: 'Quantità in ${ing['um_base']}',
      aiuto: 'Quanto ne finisce nel piatto',
    );
    if (q == null || q <= 0 || !context.mounted) return;

    final scarto = await chiediNumero(
          context,
          titolo: 'Quanto se ne perde lavorandolo?',
          etichetta: 'Scarto in percentuale',
          // Per avere 100 g di avocado nel piatto con il 30% di scarto ne
          // servono 143: la ricetta dice quanto arriva al cliente, il
          // magazzino deve scaricare quanto è uscito dalla cella.
          aiuto: 'Bucce, ritagli, cali di cottura. Zero se non se ne perde.',
          iniziale: 0,
        ) ??
        0;

    try {
      await repo.aggiungiComponente(
        distintaId: id,
        ingredienteId: ing['id'] as String,
        quantita: q,
        scarto: scarto,
      );
      _ricarica(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '$e'.contains('duplicate') || '$e'.contains('unique')
                      ? 'Quell\'ingrediente è già nella ricetta.'
                      : '$e')),
        );
      }
    }
  }

  /// Modifica il piatto o il semilavorato a cui la ricetta appartiene.
  ///
  /// Per i semilavorati riusa la scheda dell'ingrediente: sono la stessa cosa,
  /// e due schermate diverse per la stessa entità finirebbero per divergere.
  Future<void> _modificaTestata(BuildContext context, WidgetRef ref,
      Map<String, dynamic> dist, bool perProdotto) async {
    if (!perProdotto) {
      final sessione = ref.read(sessioneProvider).valueOrNull;
      if (sessione == null) return;
      final cambiato = await apriIngrediente(
        context,
        ingrediente: Map<String, dynamic>.from(dist['ingrediente'] as Map),
        organizzazioneId: sessione.organizzazioneId,
      );
      if (cambiato) _ricarica(ref);
      return;
    }

    final p = Map<String, dynamic>.from(dist['prodotto_venduto'] as Map);
    final esito = await showDialog<String>(
      context: context,
      builder: (_) => _ModificaPiatto(prodotto: p),
    );
    if (esito == null) return;

    if (esito == 'eliminato' && context.mounted) {
      ref.invalidate(prodottiProvider);
      context.go('/ricette');
      return;
    }
    _ricarica(ref);
  }

  Future<void> _modifica(
      BuildContext context, WidgetRef ref, Map<String, dynamic> c) async {
    final ing = c['ingrediente'] as Map?;
    final q = await chiediNumero(
      context,
      titolo: ing?['nome'] as String? ?? '',
      etichetta: 'Quantità in ${ing?['um_base']}',
      iniziale: c['quantita'] as num?,
    );
    if (q == null || q <= 0) return;
    await repo.aggiornaComponente(c['id'] as String, quantita: q);
    _ricarica(ref);
  }
}

/// Modifica di un piatto a menù.
///
/// Restituisce 'salvato' o 'eliminato'. Un piatto già venduto si può
/// eliminare: le righe di vendita restano e perdono solo il collegamento,
/// perché quello che è successo in cassa è successo comunque.
class _ModificaPiatto extends StatefulWidget {
  final Map<String, dynamic> prodotto;
  const _ModificaPiatto({required this.prodotto});

  @override
  State<_ModificaPiatto> createState() => _ModificaPiattoState();
}

class _ModificaPiattoState extends State<_ModificaPiatto> {
  late final _nome =
      TextEditingController(text: widget.prodotto['nome'] as String? ?? '');
  late final _categoria = TextEditingController(
      text: widget.prodotto['categoria_menu'] as String? ?? '');
  late final _codice = TextEditingController(
      text: widget.prodotto['codice_esterno'] as String? ?? '');
  late final _prezzo = TextEditingController(
      text: (widget.prodotto['prezzo_vendita'] as num?)
              ?.toString()
              .replaceAll('.', ',') ??
          '');

  late bool _senzaDistinta = widget.prodotto['senza_distinta'] == true;
  late bool _attivo = widget.prodotto['attivo'] != false;
  bool _lavorando = false;
  String? _errore;

  @override
  void dispose() {
    for (final c in [_nome, _categoria, _codice, _prezzo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salva() async {
    setState(() {
      _lavorando = true;
      _errore = null;
    });
    try {
      await repo.aggiornaProdottoVenduto(widget.prodotto['id'] as String, {
        'nome': _nome.text.trim(),
        'categoria_menu':
            _categoria.text.trim().isEmpty ? null : _categoria.text.trim(),
        'codice_esterno':
            _codice.text.trim().isEmpty ? null : _codice.text.trim(),
        'prezzo_vendita': num.tryParse(_prezzo.text.replaceAll(',', '.')),
        'senza_distinta': _senzaDistinta,
        'attivo': _attivo,
      });
      if (mounted) Navigator.pop(context, 'salvato');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errore = '$e'.contains('unique') || '$e'.contains('duplicate')
              ? 'Esiste già un piatto con questo nome.'
              : '$e';
          _lavorando = false;
        });
      }
    }
  }

  Future<void> _elimina() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Eliminare ${_nome.text.trim()}?'),
            content: const Text(
              'Sparisce il piatto e la sua ricetta. Le vendite già registrate '
              'restano: quello che è passato in cassa è passato, perde solo il '
              'collegamento al piatto.',
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

    setState(() => _lavorando = true);
    try {
      await repo.eliminaProdottoVenduto(widget.prodotto['id'] as String);
      if (mounted) Navigator.pop(context, 'eliminato');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errore = '$e';
          _lavorando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Modifica piatto'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nome,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _prezzo,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Prezzo di vendita', suffixText: '€'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _categoria,
                  decoration:
                      const InputDecoration(labelText: 'Categoria a menù'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _codice,
                  decoration: const InputDecoration(
                    labelText: 'Codice di cassa',
                    helperText: 'Come identifica il piatto iPratico. Senza, le '
                        'vendite non si agganciano da sole.',
                    helperMaxLines: 3,
                  ),
                ),
                SwitchListTile(
                  value: _senzaDistinta,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Non consuma magazzino'),
                  subtitle: const Text(
                    'Coperto, servizio, buoni. Venderlo non scarica niente e '
                    'non compare fra quelli senza ricetta.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (v) => setState(() => _senzaDistinta = v),
                ),
                SwitchListTile(
                  value: _attivo,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('A menù'),
                  subtitle: const Text(
                    'Spegnerlo lo toglie dagli elenchi senza cancellare le '
                    'vendite passate.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (v) => setState(() => _attivo = v),
                ),
                if (_errore != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_errore!,
                        style: const TextStyle(
                            color: AppColors.accentDark, fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _lavorando ? null : _elimina,
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('Elimina'),
          ),
          const Spacer(),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
          TextButton(
            onPressed:
                (_lavorando || _nome.text.trim().isEmpty) ? null : _salva,
            child: const Text('Salva'),
          ),
        ],
      );
}

class _Testata extends StatelessWidget {
  final bool perProdotto;
  final num costo;
  final num? costoUnitario;
  final String umResa;
  final num? prezzo;
  final num? resa;
  final int senzaCosto;
  final VoidCallback onCambiaResa;

  const _Testata({
    required this.perProdotto,
    required this.costo,
    required this.costoUnitario,
    required this.umResa,
    required this.prezzo,
    required this.resa,
    required this.senzaCosto,
    required this.onCambiaResa,
  });

  @override
  Widget build(BuildContext context) {
    final incidenza =
        (prezzo != null && prezzo! > 0) ? 100 * costo / prezzo! : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _riga('Costo degli ingredienti', euro(costo)),
            if (!perProdotto) ...[
              _riga('Resa della preparazione',
                  resa == null ? '—' : quantitaLeggibile(resa, umResa)),
              if (costoUnitario != null)
                _riga('Costo al chilo',
                    '${numeroIt(num.parse((costoUnitario! * 1000).toStringAsFixed(4)))} €'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCambiaResa,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Cambia resa'),
                ),
              ),
            ] else ...[
              _riga('Prezzo di vendita', euro(prezzo)),
              _riga('Margine', prezzo == null ? '—' : euro(prezzo! - costo)),
              if (incidenza != null)
                _riga('Incidenza',
                    '${numeroIt(num.parse(incidenza.toStringAsFixed(1)))}%'),
            ],
            if (senzaCosto > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                // Un costo calcolato su ingredienti senza prezzo è più basso
                // del vero. Dirlo, invece di lasciarlo credere.
                child: Text(
                  '$senzaCosto ${senzaCosto == 1 ? 'ingrediente non ha' : 'ingredienti non hanno'} '
                  'ancora un costo: il totale è più basso di quello vero.',
                  style: const TextStyle(
                      color: AppColors.accentDark, fontSize: 12.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

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

class _Componente extends StatelessWidget {
  final Map<String, dynamic> c;
  final num costoTotale;
  final VoidCallback onModifica;
  final VoidCallback onTogli;

  const _Componente({
    required this.c,
    required this.costoTotale,
    required this.onModifica,
    required this.onTogli,
  });

  @override
  Widget build(BuildContext context) {
    final ing = c['ingrediente'] as Map?;
    final um = ing?['um_base'] as String? ?? '';
    final cm = ing?['costo_medio'] as num?;
    final scarto = (c['scarto_percentuale'] as num?) ?? 0;
    final quantita = c['quantita'] as num;
    final effettiva = quantita / (1 - scarto / 100);
    final costo = cm == null ? null : effettiva * cm;
    final peso =
        (costo != null && costoTotale > 0) ? 100 * costo / costoTotale : null;

    return InkWell(
      onTap: onModifica,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ing?['nome'] as String? ?? '',
                      style: const TextStyle(fontSize: 14)),
                  Text(
                    [
                      quantitaLeggibile(quantita, um),
                      if (scarto > 0)
                        'scarto ${numeroIt(scarto)}% → ${quantitaLeggibile(num.parse(effettiva.toStringAsFixed(3)), um)}',
                      if (cm == null) 'senza costo',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (costo != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(euro(costo),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  // Quanto pesa questo ingrediente sul costo del piatto: è il
                  // numero che dice dove conviene intervenire.
                  if (peso != null)
                    Text('${numeroIt(num.parse(peso.toStringAsFixed(0)))}%',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ],
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.textMuted,
              onPressed: onTogli,
            ),
          ],
        ),
      ),
    );
  }
}
