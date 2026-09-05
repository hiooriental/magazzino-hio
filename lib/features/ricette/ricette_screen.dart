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

bool haRicetta(Map<String, dynamic> r) {
  final d = r['distinta'];
  if (d is List) return d.any((x) => x['stato'] == 'attiva');
  if (d is Map) return d['stato'] == 'attiva';
  return false;
}

String? idDistinta(Map<String, dynamic> r) {
  final d = r['distinta'];
  if (d is List) {
    for (final x in d) {
      if (x['stato'] == 'attiva') return x['id'] as String;
    }
  }
  if (d is Map && d['stato'] == 'attiva') return d['id'] as String;
  return null;
}

/// Le ricette: piatti a menù e semilavorati.
///
/// Con duecento voci a menù l'elenco piatto è inutilizzabile: qui si cerca,
/// si filtra su quelli che ancora non hanno una ricetta, e il resto è
/// raggruppato per categoria come sul menù di sala.
class RicetteScreen extends ConsumerStatefulWidget {
  const RicetteScreen({super.key});

  @override
  ConsumerState<RicetteScreen> createState() => _RicetteScreenState();
}

class _RicetteScreenState extends ConsumerState<RicetteScreen> {
  final _cerca = TextEditingController();
  bool _semilavorati = false;
  bool _soloSenzaRicetta = false;

  @override
  void dispose() {
    _cerca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessione = ref.watch(sessioneProvider).valueOrNull;
    final prodotti = ref.watch(prodottiProvider);

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
              onPressed: () => _nuovoPiatto(sessione, prodotti.valueOrNull),
              icon: const Icon(Icons.add),
              label: const Text('Nuovo piatto'),
            ),
      body: ContenutoCentrato(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Piatti')),
                      ButtonSegment(value: true, label: Text('Semilavorati')),
                    ],
                    selected: {_semilavorati},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _semilavorati = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cerca,
                    decoration: InputDecoration(
                      hintText: 'Cerca',
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
                      label: const Text('Solo senza ricetta'),
                      selected: _soloSenzaRicetta,
                      showCheckmark: true,
                      onSelected: (v) => setState(() => _soloSenzaRicetta = v),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _semilavorati
                  ? _Elenco(
                      provider: semilavoratiProvider,
                      cerca: _cerca.text,
                      soloSenza: _soloSenzaRicetta,
                      semilavorati: true,
                      vuoto:
                          'Nessun semilavorato.\n\nUn semilavorato è un ingrediente '
                          'che si produce invece di comprarlo: riso condito, salse, '
                          'brodi, tranci ricavati da un pezzo intero.',
                    )
                  : _Elenco(
                      provider: prodottiProvider,
                      cerca: _cerca.text,
                      soloSenza: _soloSenzaRicetta,
                      semilavorati: false,
                      vuoto: 'Nessun piatto in anagrafica.',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _nuovoPiatto(
      Sessione sessione, List<Map<String, dynamic>>? esistenti) async {
    // Le categorie non hanno una tabella loro: sono quelle già usate dai
    // piatti. Una tabella in più andrebbe tenuta allineata al menù di sala,
    // e sarebbe una cosa in più che può divergere.
    final categorie = <String>{
      for (final p in esistenti ?? const <Map<String, dynamic>>[])
        if ((p['categoria_menu'] as String?)?.isNotEmpty ?? false)
          p['categoria_menu'] as String
    }.toList()
      ..sort();

    final dati = await showDialog<_NuovoPiatto>(
      context: context,
      builder: (_) => _DialogoNuovoPiatto(categorie: categorie),
    );
    if (dati == null) return;

    try {
      final id = await repo.creaProdottoVenduto(
        organizzazioneId: sessione.organizzazioneId,
        nome: dati.nome,
        codiceEsterno: dati.codice,
        categoria: dati.categoria,
        prezzo: dati.prezzo,
      );
      final distinta = await repo.distintaAttiva(
        organizzazioneId: sessione.organizzazioneId,
        prodottoVendutoId: id,
      );
      ref.invalidate(prodottiProvider);
      if (mounted) context.go('/ricette/$distinta');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'.contains('duplicate') || '$e'.contains('unique')
              ? 'Esiste già un piatto con questo nome.'
              : '$e'),
        ));
      }
    }
  }
}

class _Elenco extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<Map<String, dynamic>>>> provider;
  final String cerca;
  final bool soloSenza;
  final bool semilavorati;
  final String vuoto;

  const _Elenco({
    required this.provider,
    required this.cerca,
    required this.soloSenza,
    required this.semilavorati,
    required this.vuoto,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(provider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (tutte) {
          final q = cerca.trim().toLowerCase();
          final righe = tutte.where((r) {
            if (soloSenza && haRicetta(r)) return false;
            if (q.isEmpty) return true;
            final n = (r['nome'] as String? ?? '').toLowerCase();
            final c = (r['categoria_menu'] as String? ?? '').toLowerCase();
            return n.contains(q) || c.contains(q);
          }).toList();

          if (tutte.isEmpty) return _Messaggio(vuoto);
          if (righe.isEmpty) {
            return _Messaggio(soloSenza
                ? 'Tutto quello che cercavi ha già una ricetta.'
                : 'Nessun risultato per «$cerca».');
          }

          // Raggruppati per categoria, come sul menù di sala: con
          // duecento voci è l'unico modo per ritrovarle.
          final gruppi = <String, List<Map<String, dynamic>>>{};
          for (final r in righe) {
            final c = semilavorati
                ? 'Semilavorati'
                : (r['categoria_menu'] as String? ?? 'Senza categoria');
            gruppi.putIfAbsent(c, () => []).add(r);
          }
          final chiavi = gruppi.keys.toList()..sort();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              for (final c in chiavi) ...[
                _Intestazione(
                  titolo: c,
                  totale: gruppi[c]!.length,
                  conRicetta: gruppi[c]!.where(haRicetta).length,
                ),
                ...gruppi[c]!
                    .map((r) => _Riga(r: r, semilavorato: semilavorati)),
                const SizedBox(height: 14),
              ],
            ],
          );
        },
      );
}

class _Intestazione extends StatelessWidget {
  final String titolo;
  final int totale;
  final int conRicetta;

  const _Intestazione({
    required this.titolo,
    required this.totale,
    required this.conRicetta,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                titolo,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.goldDark,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            Text(
              '$conRicetta su $totale',
              style:
                  const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ),
      );
}

class _Riga extends ConsumerWidget {
  final Map<String, dynamic> r;
  final bool semilavorato;
  const _Riga({required this.r, required this.semilavorato});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ha = haRicetta(r);
    final senza = r['senza_distinta'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        child: ListTile(
          dense: true,
          title: Text(r['nome'] as String? ?? ''),
          subtitle: Text(
            semilavorato
                ? (r['costo_medio'] == null
                    ? 'in ${r['um_base']} · nessun costo ancora'
                    : 'in ${r['um_base']} · '
                        '${numeroIt((r['costo_medio'] as num) * 1000)} €/kg')
                : [
                    if (r['prezzo_vendita'] != null)
                      euro(r['prezzo_vendita'] as num?)
                    else
                      'senza prezzo',
                    if (r['codice_esterno'] == null) 'senza codice di cassa',
                  ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: senza
              ? const Text('non consuma\nmagazzino',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10.5, color: AppColors.textMuted))
              : Icon(
                  ha ? Icons.check_circle_outline : Icons.add_circle_outline,
                  color:
                      ha ? AppColors.statoConfermato : AppColors.rigaProposta,
                ),
          onTap: senza ? null : () => _apri(context, ref),
        ),
      ),
    );
  }

  Future<void> _apri(BuildContext context, WidgetRef ref) async {
    final sessione = ref.read(sessioneProvider).valueOrNull;
    if (sessione == null) return;

    var id = idDistinta(r);
    if (id == null) {
      num? resa;
      if (semilavorato) {
        // La resa serve a dividere il costo degli ingredienti sulla quantità
        // prodotta: senza, il costo unitario non si può calcolare.
        resa = await chiediResa(
            context, r['nome'] as String, r['um_base'] as String);
        if (resa == null) return;
      }
      id = await repo.distintaAttiva(
        organizzazioneId: sessione.organizzazioneId,
        prodottoVendutoId: semilavorato ? null : r['id'] as String,
        ingredienteId: semilavorato ? r['id'] as String : null,
        quantitaProdotta: resa,
      );
    }
    if (context.mounted) context.go('/ricette/$id');
  }
}

// ── Nuovo piatto ───────────────────────────────────────────────────────────

class _NuovoPiatto {
  final String nome;
  final String? categoria;
  final String? codice;
  final num? prezzo;
  const _NuovoPiatto(this.nome, this.categoria, this.codice, this.prezzo);
}

class _DialogoNuovoPiatto extends StatefulWidget {
  final List<String> categorie;
  const _DialogoNuovoPiatto({required this.categorie});

  @override
  State<_DialogoNuovoPiatto> createState() => _DialogoNuovoPiattoState();
}

class _DialogoNuovoPiattoState extends State<_DialogoNuovoPiatto> {
  final _nome = TextEditingController();
  final _codice = TextEditingController();
  final _prezzo = TextEditingController();
  final _nuovaCategoria = TextEditingController();

  String? _categoria;
  bool _categoriaNuova = false;

  static const _altra = '__altra__';

  @override
  void dispose() {
    _nome.dispose();
    _codice.dispose();
    _prezzo.dispose();
    _nuovaCategoria.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo piatto'),
      // Larghezza fissa: nel dialogo di serie il testo d'aiuto veniva
      // tagliato a metà parola.
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nome,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nome'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _prezzo,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Prezzo di vendita',
                  suffixText: '€',
                ),
              ),
              const SizedBox(height: 14),

              // Le categorie sono quelle già a menù: sceglierne una esistente
              // evita di ritrovarsi "SECONDI" e "Secondi" come due cose
              // diverse.
              DropdownButtonFormField<String>(
                value: _categoria,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Categoria a menù'),
                items: [
                  ...widget.categorie
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  const DropdownMenuItem(
                    value: _altra,
                    child: Text('Nuova categoria…',
                        style: TextStyle(color: AppColors.goldDark)),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _categoriaNuova = v == _altra;
                  _categoria = _categoriaNuova ? null : v;
                }),
              ),
              if (_categoriaNuova) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _nuovaCategoria,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Nome della nuova categoria',
                  ),
                ),
              ],

              const SizedBox(height: 14),
              TextField(
                controller: _codice,
                decoration: const InputDecoration(
                  labelText: 'Codice di cassa',
                  helperText:
                      'Come identifica il piatto iPratico. Senza, le vendite '
                      'non si agganciano da sole. Si può aggiungere dopo.',
                  helperMaxLines: 3,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla')),
        TextButton(
          onPressed: _nome.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _NuovoPiatto(
                      _nome.text.trim(),
                      _categoriaNuova
                          ? _nuovaCategoria.text.trim()
                          : _categoria,
                      _codice.text.trim(),
                      num.tryParse(_prezzo.text.replaceAll(',', '.')),
                    ),
                  ),
          child: const Text('Crea'),
        ),
      ],
    );
  }
}

/// Quanto ne esce da una preparazione intera.
Future<num?> chiediResa(BuildContext context, String nome, String um) async {
  final c = TextEditingController();
  final v = await showDialog<num>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Quanto $nome esce da una preparazione?'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Resa in $um',
            helperText: 'Il peso finito, non la somma degli ingredienti',
            helperMaxLines: 2,
          ),
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
