import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          appBar: AppBar(title: Text(nome)),
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
