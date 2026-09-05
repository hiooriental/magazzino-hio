import 'package:flutter/material.dart';

import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';

/// Il pannello che compare toccando una riga da risolvere.
///
/// È il punto in cui il sistema impara, quindi è anche l'unico posto dove
/// all'operatore si chiede di pensare. Vale la pena chiedergli poco e una
/// volta sola: quello che decide qui diventa un alias, e dal documento
/// successivo quella riga passa da sé.
class AbbinaSheet extends StatefulWidget {
  final Map<String, dynamic> riga;
  const AbbinaSheet({super.key, required this.riga});

  @override
  State<AbbinaSheet> createState() => _AbbinaSheetState();
}

class _AbbinaSheetState extends State<AbbinaSheet> {
  final _ricerca = TextEditingController();
  final _fattore = TextEditingController();
  final _nomeNuovo = TextEditingController();

  List<Map<String, dynamic>> _ingredienti = const [];
  List<Map<String, dynamic>> _categorie = const [];

  Map<String, dynamic>? _scelto; // ingrediente esistente selezionato
  bool _creaNuovo = false;
  String _umBase = 'g';
  String? _categoriaId;
  String _conservazione = 'ambiente';
  bool _gestisciLotti = false;
  bool _abbattimento = false;

  bool _serveFattore = false;
  bool _caricando = true;
  bool _salvando = false;
  String? _errore;

  String get _um => widget.riga['um_dichiarata'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    // Il nome parte dalla descrizione del fornitore: nove volte su dieci
    // basta ripulirla, ed è meno faticoso che scriverla da capo.
    //
    // Solo la PRIMA riga, però: certi fornitori infilano sotto al nome le
    // misure, il codice interno e il riferimento all'ordine. In un campo a
    // riga singola quei capoversi spariscono e le parole si attaccano
    // ("COMPOFIL 250 HS APMeasures 2.300m..."). Il nome dell'articolo è la
    // prima riga; il resto è contorno, e sta comunque nell'intestazione qui
    // sopra se serve guardarlo.
    final descrizione = widget.riga['descrizione_originale'] as String? ?? '';
    _nomeNuovo.text = descrizione
        .split(RegExp(r'[\r\n]'))
        .first
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    _carica();
  }

  @override
  void dispose() {
    _ricerca.dispose();
    _fattore.dispose();
    _nomeNuovo.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    try {
      final ing = await repo.cercaIngredienti(_ricerca.text);
      final cat = await repo.categorie();
      if (!mounted) return;
      setState(() {
        _ingredienti = ing;
        _categorie = cat;
        _caricando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errore = '$e';
          _caricando = false;
        });
      }
    }
  }

  /// Chiede al database se sa già convertire l'unità del documento.
  ///
  /// La domanda va fatta a lui e non ripetuta qui: `converti_um` è la stessa
  /// funzione che userà il riconoscimento, e due copie della stessa regola
  /// prima o poi divergono.
  Future<void> _verificaFattore(String umBase) async {
    final automatico = await repo.fattoreAutomatico(_um, umBase);
    if (mounted) setState(() => _serveFattore = automatico == null);
  }

  Future<void> _salva() async {
    setState(() {
      _salvando = true;
      _errore = null;
    });
    try {
      final fattore = num.tryParse(_fattore.text.replaceAll(',', '.'));

      final esito = _creaNuovo
          ? await repo.creaIngredienteEAbbina(
              rigaId: widget.riga['id'] as String,
              nome: _nomeNuovo.text.trim(),
              umBase: _umBase,
              fattoreConversione: fattore,
              categoriaId: _categoriaId,
              conservazione: _conservazione,
              gestisciLotti: _gestisciLotti,
              richiedeAbbattimento: _abbattimento,
            )
          : await repo.abbina(
              rigaId: widget.riga['id'] as String,
              ingredienteId: _scelto!['id'] as String,
              fattoreConversione: fattore,
            );

      if (mounted) Navigator.of(context).pop(esito);
    } catch (e) {
      // I messaggi delle funzioni SQL sono già scritti per essere letti da
      // una persona ("Serve il fattore di conversione: quante g stanno in
      // una unità d'acquisto CT?"): si mostrano così come sono.
      if (mounted) {
        setState(() {
          _errore = _messaggio(e);
          _salvando = false;
        });
      }
    }
  }

  bool get _puoSalvare {
    if (_salvando) return false;
    if (_creaNuovo && _nomeNuovo.text.trim().isEmpty) return false;
    if (!_creaNuovo && _scelto == null) return false;
    if (_serveFattore &&
        num.tryParse(_fattore.text.replaceAll(',', '.')) == null) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                _IntestazioneRiga(riga: widget.riga),
                const SizedBox(height: 20),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Già esistente')),
                    ButtonSegment(value: true, label: Text('Nuovo')),
                  ],
                  selected: {_creaNuovo},
                  onSelectionChanged: (s) {
                    setState(() {
                      _creaNuovo = s.first;
                      _scelto = null;
                    });
                    if (_creaNuovo) _verificaFattore(_umBase);
                  },
                ),
                const SizedBox(height: 16),
                if (_caricando)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_creaNuovo)
                  ..._formNuovo()
                else
                  ..._elencoEsistenti(),
                if (_serveFattore) ...[
                  const SizedBox(height: 20),
                  _CampoFattore(
                    controller: _fattore,
                    umDocumento: _um,
                    umBase: _creaNuovo
                        ? _umBase
                        : (_scelto?['um_base'] as String? ?? ''),
                    onChanged: () => setState(() {}),
                  ),
                ],
                if (_errore != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_errore!,
                        style: const TextStyle(color: AppColors.accentDark)),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _puoSalvare ? _salva : null,
                  child: _salvando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Abbina'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _elencoEsistenti() => [
        TextField(
          controller: _ricerca,
          decoration: const InputDecoration(
            labelText: 'Cerca un ingrediente',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => _carica(),
        ),
        const SizedBox(height: 12),
        if (_ingredienti.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nessun ingrediente trovato. Se è un prodotto nuovo, passa a "Nuovo".',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ..._ingredienti.map((i) => RadioListTile<String>(
                value: i['id'] as String,
                groupValue: _scelto?['id'] as String?,
                contentPadding: EdgeInsets.zero,
                title: Text(i['nome'] as String),
                subtitle: Text('in ${i['um_base']}',
                    style: const TextStyle(color: AppColors.textMuted)),
                onChanged: (_) {
                  setState(() => _scelto = i);
                  _verificaFattore(i['um_base'] as String);
                },
              )),
      ];

  List<Widget> _formNuovo() => [
        TextField(
          controller: _nomeNuovo,
          decoration: const InputDecoration(
            labelText: 'Nome dell\'ingrediente',
            helperText: 'Come lo chiami tu, non come lo scrive il fornitore',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        const Text('Unità di misura di magazzino',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'g', label: Text('grammi')),
            ButtonSegment(value: 'ml', label: Text('millilitri')),
            ButtonSegment(value: 'pz', label: Text('pezzi')),
          ],
          selected: {_umBase},
          onSelectionChanged: (s) {
            setState(() => _umBase = s.first);
            _verificaFattore(s.first);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _categoriaId,
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: _categorie
              .map((c) => DropdownMenuItem(
                  value: c['id'] as String, child: Text(c['nome'] as String)))
              .toList(),
          onChanged: (v) => setState(() => _categoriaId = v),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _conservazione,
          decoration: const InputDecoration(labelText: 'Conservazione'),
          items: const [
            DropdownMenuItem(value: 'ambiente', child: Text('Ambiente')),
            DropdownMenuItem(value: 'frigo', child: Text('Frigorifero')),
            DropdownMenuItem(value: 'freezer', child: Text('Freezer')),
          ],
          onChanged: (v) => setState(() => _conservazione = v ?? 'ambiente'),
        ),
        SwitchListTile(
          value: _gestisciLotti,
          contentPadding: EdgeInsets.zero,
          title: const Text('Gestisci i lotti'),
          subtitle: const Text(
            'Ogni carico genera un lotto tracciabile. Utile per il fresco, '
            'inutile per tovaglioli e detersivi.',
            style: TextStyle(fontSize: 12),
          ),
          onChanged: (v) => setState(() => _gestisciLotti = v),
        ),
        SwitchListTile(
          value: _abbattimento,
          contentPadding: EdgeInsets.zero,
          title: const Text('Richiede abbattimento'),
          subtitle: const Text(
            'Pesce destinato al consumo crudo. Genera sempre un lotto e '
            'chiede la registrazione dell\'abbattimento.',
            style: TextStyle(fontSize: 12),
          ),
          onChanged: (v) => setState(() {
            _abbattimento = v;
            if (v) _gestisciLotti = true;
          }),
        ),
      ];
}

/// Cosa c'era scritto sul documento. Serve a decidere senza dover tornare
/// alla foto.
class _IntestazioneRiga extends StatelessWidget {
  final Map<String, dynamic> riga;
  const _IntestazioneRiga({required this.riga});

  @override
  Widget build(BuildContext context) {
    final letto = [
      if (riga['quantita_testo'] != null)
        '${riga['quantita_testo']} ${riga['um_dichiarata'] ?? ''}',
      if (riga['prezzo_testo'] != null) '× ${riga['prezzo_testo']}',
      if (riga['totale_testo'] != null) '= ${riga['totale_testo']}',
    ].join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(riga['descrizione_originale'] as String? ?? '',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (riga['codice_fornitore_originale'] != null)
          Text('Codice fornitore: ${riga['codice_fornitore_originale']}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        if (letto.isNotEmpty)
          Text(letto, style: const TextStyle(color: AppColors.textSecondary)),
        if (riga['note'] != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(riga['note'] as String,
                style:
                    const TextStyle(color: AppColors.accentDark, fontSize: 13)),
          ),
        ],
      ],
    );
  }
}

class _CampoFattore extends StatelessWidget {
  final TextEditingController controller;
  final String umDocumento;
  final String umBase;
  final VoidCallback onChanged;

  const _CampoFattore({
    required this.controller,
    required this.umDocumento,
    required this.umBase,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: 'Quanti $umBase in un "$umDocumento"?',
          // "CT" non dice quanto pesa. Senza questo numero la giacenza
          // conterebbe colli invece di merce, e non servirebbe a niente.
          helperText: 'Cartone da 4×2,5 kg di un ingrediente in grammi → 10000',
          helperMaxLines: 2,
          prefixIcon: const Icon(Icons.straighten),
        ),
      );
}

String _messaggio(Object e) {
  final s = e.toString();
  // Le eccezioni PostgREST arrivano come "PostgrestException(message: ..., ...)":
  // all'operatore interessa solo il messaggio.
  final m = RegExp(r'message:\s*(.+?),\s*code:').firstMatch(s);
  return m != null ? m.group(1)! : s;
}
