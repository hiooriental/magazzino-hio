import 'package:flutter/material.dart';

import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';

/// La scheda di un ingrediente: si apre per crearlo o per modificarlo.
///
/// Restituisce `true` se qualcosa è cambiato.
Future<bool> apriIngrediente(
  BuildContext context, {
  Map<String, dynamic>? ingrediente,
  required String organizzazioneId,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Scheda(
        ingrediente: ingrediente,
        organizzazioneId: organizzazioneId,
      ),
    ) ??
    false;

class _Scheda extends StatefulWidget {
  final Map<String, dynamic>? ingrediente;
  final String organizzazioneId;

  const _Scheda({required this.ingrediente, required this.organizzazioneId});

  @override
  State<_Scheda> createState() => _SchedaState();
}

class _SchedaState extends State<_Scheda> {
  final _nome = TextEditingController();
  final _dose = TextEditingController();
  final _scortaMin = TextEditingController();
  final _scortaIdeale = TextEditingController();
  final _giorni = TextEditingController();
  final _note = TextEditingController();

  String _um = 'g';
  String _conservazione = 'ambiente';
  String? _categoriaId;
  bool _interno = false;
  bool _vendibile = false;
  bool _lotti = false;
  bool _abbattimento = false;
  bool _attivo = true;

  List<Map<String, dynamic>> _categorie = const [];
  bool _umBloccata = false;
  bool _caricando = true;
  bool _salvando = false;
  String? _errore;

  bool get _nuovo => widget.ingrediente == null;

  @override
  void initState() {
    super.initState();
    final i = widget.ingrediente;
    if (i != null) {
      _nome.text = i['nome'] as String? ?? '';
      _um = i['um_base'] as String? ?? 'g';
      _conservazione = i['conservazione'] as String? ?? 'ambiente';
      _categoriaId = i['categoria_id'] as String?;
      _interno = i['prodotto_internamente'] == true;
      _vendibile = i['vendibile_diretto'] == true;
      _lotti = i['gestisci_lotti'] == true;
      _abbattimento = i['richiede_abbattimento'] == true;
      _attivo = i['attivo'] != false;
      _dose.text = _testo(i['dose_standard']);
      _scortaMin.text = _testo(i['scorta_minima']);
      _scortaIdeale.text = _testo(i['scorta_ideale']);
      _giorni.text = _testo(i['giorni_scadenza_default']);
      _note.text = i['note'] as String? ?? '';
    }
    _carica();
  }

  static String _testo(dynamic v) =>
      v == null ? '' : v.toString().replaceAll('.', ',');

  static num? _numero(TextEditingController c) =>
      num.tryParse(c.text.replaceAll(',', '.'));

  @override
  void dispose() {
    for (final c in [_nome, _dose, _scortaMin, _scortaIdeale, _giorni, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carica() async {
    final cat = await repo.categorie();
    var bloccata = false;
    if (!_nuovo) {
      bloccata = await repo.haMovimenti(widget.ingrediente!['id'] as String);
    }
    if (mounted) {
      setState(() {
        _categorie = cat;
        _umBloccata = bloccata;
        _caricando = false;
      });
    }
  }

  Future<void> _salva() async {
    setState(() {
      _salvando = true;
      _errore = null;
    });

    final dati = <String, dynamic>{
      'nome': _nome.text.trim(),
      'conservazione': _conservazione,
      'categoria_id': _categoriaId,
      'prodotto_internamente': _interno,
      'vendibile_diretto': _vendibile,
      'gestisci_lotti': _lotti || _abbattimento,
      'richiede_abbattimento': _abbattimento,
      'attivo': _attivo,
      'dose_standard': _numero(_dose),
      'scorta_minima': _numero(_scortaMin),
      'scorta_ideale': _numero(_scortaIdeale),
      'giorni_scadenza_default': int.tryParse(_giorni.text.trim()),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      if (!_umBloccata) 'um_base': _um,
    };

    try {
      if (_nuovo) {
        dati['organizzazione_id'] = widget.organizzazioneId;
        dati['um_base'] = _um;
        await repo.creaIngrediente(dati);
      } else {
        await repo.aggiornaIngrediente(
            widget.ingrediente!['id'] as String, dati);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errore = '$e'.contains('unique') || '$e'.contains('duplicate')
              ? 'Esiste già un ingrediente con questo nome.'
              : '$e';
          _salvando = false;
        });
      }
    }
  }

  /// Eliminare non è disattivare, e la differenza conta.
  ///
  /// Un ingrediente che ha movimenti o che compare in una ricetta non si
  /// cancella: il database lo rifiuta, e fa bene — cancellarlo vorrebbe dire
  /// buttare via la storia di quei movimenti. Lì si spegne, e sparisce dagli
  /// elenchi senza portarsi via niente.
  Future<void> _elimina() async {
    final conStoria = _umBloccata;

    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(conStoria
                ? 'Questo ingrediente ha una storia'
                : 'Eliminare ${_nome.text.trim()}?'),
            content: Text(
              conStoria
                  ? 'Ci sono movimenti registrati, quindi non si può '
                      'cancellare senza buttare via la loro storia.\n\n'
                      'Posso spegnerlo: sparisce dagli elenchi e dalle '
                      'ricerche, ma resta tutto quello che è passato.'
                  : 'Non ha movimenti né ricette: sparisce del tutto.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Annulla')),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: Text(conStoria ? 'Spegni' : 'Elimina'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _salvando = true);
    final id = widget.ingrediente!['id'] as String;

    try {
      if (conStoria) {
        await repo.aggiornaIngrediente(id, {'attivo': false});
      } else {
        await repo.eliminaIngrediente(id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          // Il caso tipico: compare in una ricetta. Il vincolo del database
          // parla di chiavi esterne, all'operatore serve un'altra frase.
          _errore = '$e'.contains('foreign key') || '$e'.contains('violates')
              ? 'Non si può eliminare: è usato in una ricetta o ha dei '
                  'movimenti. Spegnilo con l\'interruttore «Attivo».'
              : '$e';
          _salvando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
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
            child: _caricando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                          _nuovo ? 'Nuovo ingrediente' : 'Modifica ingrediente',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _nome,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Nome',
                          helperText:
                              'Come lo chiami tu, non come lo scrive il fornitore',
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 18),
                      const _Etichetta('Unità di magazzino'),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'g', label: Text('grammi')),
                          ButtonSegment(value: 'ml', label: Text('millilitri')),
                          ButtonSegment(value: 'pz', label: Text('pezzi')),
                        ],
                        selected: {_um},
                        showSelectedIcon: false,
                        onSelectionChanged: _umBloccata
                            ? null
                            : (s) => setState(() => _um = s.first),
                      ),
                      if (_umBloccata)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            // Cambiarla adesso trasformerebbe 500 g in 500 ml
                            // su tutti i movimenti già registrati.
                            'Non si può più cambiare: ci sono già movimenti '
                            'registrati in questa unità.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        value: _categoriaId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Categoria'),
                        items: _categorie
                            .map((c) => DropdownMenuItem(
                                value: c['id'] as String,
                                child: Text(c['nome'] as String)))
                            .toList(),
                        onChanged: (v) => setState(() => _categoriaId = v),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _conservazione,
                        decoration:
                            const InputDecoration(labelText: 'Conservazione'),
                        items: const [
                          DropdownMenuItem(
                              value: 'ambiente', child: Text('Ambiente')),
                          DropdownMenuItem(
                              value: 'frigo', child: Text('Frigorifero')),
                          DropdownMenuItem(
                              value: 'freezer', child: Text('Freezer')),
                        ],
                        onChanged: (v) =>
                            setState(() => _conservazione = v ?? 'ambiente'),
                      ),
                      const SizedBox(height: 18),
                      const _Etichetta('Come si comporta'),
                      SwitchListTile(
                        value: _interno,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Si produce in casa'),
                        subtitle: const Text(
                          'Salse, brodi, riso condito, tagli ricavati da un '
                          'pezzo intero. Ha una ricetta e un costo che nasce '
                          'dalle lavorazioni invece che dagli acquisti.',
                          style: TextStyle(fontSize: 12),
                        ),
                        onChanged: (v) => setState(() => _interno = v),
                      ),
                      SwitchListTile(
                        value: _vendibile,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Si vende anche così com\'è'),
                        subtitle: const Text(
                          'Il caso del bar: la bottiglia di gin è insieme '
                          'prodotto venduto e componente dei cocktail.',
                          style: TextStyle(fontSize: 12),
                        ),
                        onChanged: (v) => setState(() => _vendibile = v),
                      ),
                      if (_vendibile) ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: _dose,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Dose standard in $_um',
                            helperText:
                                'Quanto se ne versa a bicchiere. 45 per una '
                                'mescita da 4,5 cl.',
                            helperMaxLines: 2,
                          ),
                        ),
                      ],
                      SwitchListTile(
                        value: _abbattimento,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Richiede abbattimento'),
                        subtitle: const Text(
                          'Pesce destinato al consumo crudo. Ogni lotto che '
                          'entra compare fra quelli da trattare finché non è '
                          'registrato.',
                          style: TextStyle(fontSize: 12),
                        ),
                        onChanged: (v) => setState(() {
                          _abbattimento = v;
                          if (v) _lotti = true;
                        }),
                      ),
                      SwitchListTile(
                        value: _lotti || _abbattimento,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Gestisci i lotti'),
                        subtitle: const Text(
                          'Ogni carico genera un lotto tracciabile. Utile sul '
                          'fresco, inutile su tovaglioli e detersivi.',
                          style: TextStyle(fontSize: 12),
                        ),
                        onChanged: _abbattimento
                            ? null
                            : (v) => setState(() => _lotti = v),
                      ),
                      const SizedBox(height: 12),
                      const _Etichetta('Scorte e scadenze'),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _scortaMin,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: 'Scorta minima ($_um)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _scortaIdeale,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: 'Scorta ideale ($_um)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        // La soglia fissa è un aiuto, non il criterio: quello
                        // vero sono i giorni di copertura sul consumo reale.
                        'Facoltative: senza, le scorte si giudicano sui giorni '
                        'di copertura calcolati dal consumo vero.',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _giorni,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Giorni di scadenza dal carico',
                          helperText:
                              'Se lo indichi, i lotti nascono già con la loro data.',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _note,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Note'),
                      ),
                      if (!_nuovo) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: _attivo,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Attivo'),
                          subtitle: const Text(
                            'Spegnerlo lo toglie dagli elenchi senza cancellare '
                            'la sua storia di movimenti.',
                            style: TextStyle(fontSize: 12),
                          ),
                          onChanged: (v) => setState(() => _attivo = v),
                        ),
                      ],
                      if (_errore != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.accentLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_errore!,
                              style:
                                  const TextStyle(color: AppColors.accentDark)),
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  if (!_nuovo) ...[
                    OutlinedButton.icon(
                      onPressed: _salvando ? null : _elimina,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Elimina'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_salvando || _nome.text.trim().isEmpty)
                          ? null
                          : _salva,
                      child: Text(_nuovo ? 'Crea' : 'Salva'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Etichetta extends StatelessWidget {
  final String testo;
  const _Etichetta(this.testo);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          testo,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.goldDark,
            letterSpacing: 0.3,
          ),
        ),
      );
}
