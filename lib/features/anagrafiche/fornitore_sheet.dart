import 'package:flutter/material.dart';

import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';

const giorniSettimana = [
  'lunedì',
  'martedì',
  'mercoledì',
  'giovedì',
  'venerdì',
  'sabato',
  'domenica',
];

/// La scheda di un fornitore. Restituisce `true` se qualcosa è cambiato.
Future<bool> apriFornitore(
  BuildContext context, {
  Map<String, dynamic>? fornitore,
  required String organizzazioneId,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _Scheda(
        fornitore: fornitore,
        organizzazioneId: organizzazioneId,
      ),
    ) ??
    false;

class _Scheda extends StatefulWidget {
  final Map<String, dynamic>? fornitore;
  final String organizzazioneId;

  const _Scheda({required this.fornitore, required this.organizzazioneId});

  @override
  State<_Scheda> createState() => _SchedaState();
}

class _SchedaState extends State<_Scheda> {
  final _denominazione = TextEditingController();
  final _piva = TextEditingController();
  final _cf = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _referente = TextEditingController();
  final _note = TextEditingController();

  final _giorni = <String>{};
  bool _attivo = true;
  bool _conStoria = false;
  bool _caricando = true;
  bool _salvando = false;
  String? _errore;

  bool get _nuovo => widget.fornitore == null;

  @override
  void initState() {
    super.initState();
    final f = widget.fornitore;
    if (f != null) {
      _denominazione.text = f['denominazione'] as String? ?? '';
      _piva.text = f['partita_iva'] as String? ?? '';
      _cf.text = f['codice_fiscale'] as String? ?? '';
      _email.text = f['email'] as String? ?? '';
      _telefono.text = f['telefono'] as String? ?? '';
      _referente.text = f['referente'] as String? ?? '';
      _note.text = f['note'] as String? ?? '';
      _attivo = f['attivo'] != false;
      final g = f['giorni_consegna'];
      if (g is List) _giorni.addAll(g.map((x) => x.toString()));
    }
    _carica();
  }

  @override
  void dispose() {
    for (final c in [
      _denominazione,
      _piva,
      _cf,
      _email,
      _telefono,
      _referente,
      _note
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carica() async {
    var storia = false;
    if (!_nuovo) {
      storia = await repo.haDocumenti(widget.fornitore!['id'] as String);
    }
    if (mounted) {
      setState(() {
        _conStoria = storia;
        _caricando = false;
      });
    }
  }

  Future<void> _salva() async {
    setState(() {
      _salvando = true;
      _errore = null;
    });

    // La partita IVA si normalizza sempre: "IT01346641218" e "01346641218"
    // sono lo stesso fornitore, ed è così che le fatture lo ritroveranno.
    final piva = _piva.text.replaceAll(RegExp(r'\D'), '');

    final dati = <String, dynamic>{
      'denominazione': _denominazione.text.trim(),
      'partita_iva': piva.isEmpty ? null : piva,
      'codice_fiscale':
          _cf.text.trim().isEmpty ? null : _cf.text.trim().toUpperCase(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'telefono': _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
      'referente':
          _referente.text.trim().isEmpty ? null : _referente.text.trim(),
      'giorni_consegna': _giorni.isEmpty
          ? null
          : giorniSettimana.where(_giorni.contains).toList(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'attivo': _attivo,
    };

    try {
      if (_nuovo) {
        dati['organizzazione_id'] = widget.organizzazioneId;
        await repo.creaFornitore(dati);
      } else {
        await repo.aggiornaFornitore(widget.fornitore!['id'] as String, dati);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errore = '$e'.contains('unique') || '$e'.contains('duplicate')
              // È il vincolo sulla partita IVA: esiste già lo stesso fornitore
              // con un nome scritto diversamente.
              ? 'C\'è già un fornitore con questa partita IVA.'
              : '$e';
          _salvando = false;
        });
      }
    }
  }

  Future<void> _elimina() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(_conStoria
                ? 'Questo fornitore ha una storia'
                : 'Eliminare ${_denominazione.text.trim()}?'),
            content: Text(
              _conStoria
                  ? 'Ha già portato dei documenti, quindi non si può '
                      'cancellare senza buttare via anche quelli.\n\n'
                      'Posso spegnerlo: sparisce dagli elenchi, ma i suoi '
                      'carichi e i prezzi che hai pagato restano.'
                  : 'Non ha documenti: sparisce del tutto, insieme agli '
                      'articoli che gli erano stati abbinati.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Annulla')),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: Text(_conStoria ? 'Spegni' : 'Elimina'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _salvando = true);
    final id = widget.fornitore!['id'] as String;
    try {
      if (_conStoria) {
        await repo.aggiornaFornitore(id, {'attivo': false});
      } else {
        await repo.eliminaFornitore(id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errore = '$e'.contains('foreign key') || '$e'.contains('violates')
              ? 'Non si può eliminare: ha dei documenti collegati. Spegnilo '
                  'con l\'interruttore «Attivo».'
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
                      Text(_nuovo ? 'Nuovo fornitore' : 'Modifica fornitore',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _denominazione,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            const InputDecoration(labelText: 'Denominazione'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _piva,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Partita IVA',
                          helperText:
                              'È la chiave con cui le fatture elettroniche lo '
                              'riconosceranno da sole. Il prefisso IT si può '
                              'lasciare: viene tolto.',
                          helperMaxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _cf,
                        decoration:
                            const InputDecoration(labelText: 'Codice fiscale'),
                      ),
                      const SizedBox(height: 18),
                      const _Etichetta('Contatti'),
                      TextField(
                        controller: _referente,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Referente',
                          helperText: 'Chi risponde quando chiami per ordinare',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _telefono,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: 'Telefono'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 18),
                      const _Etichetta('Giorni di consegna'),
                      const Text(
                        // Serve a sapere entro quando ordinare: un fornitore
                        // che passa il martedì va chiamato il lunedì.
                        'Quando passa. Serve a capire entro quando ordinare.',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: giorniSettimana
                            .map((g) => FilterChip(
                                  label: Text(g.substring(0, 3)),
                                  selected: _giorni.contains(g),
                                  onSelected: (v) => setState(() {
                                    if (v) {
                                      _giorni.add(g);
                                    } else {
                                      _giorni.remove(g);
                                    }
                                  }),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _note,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          helperText:
                              'Ordini minimi, orari, come si preferisce essere '
                              'contattati.',
                          helperMaxLines: 2,
                        ),
                      ),
                      if (!_nuovo) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: _attivo,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Attivo'),
                          subtitle: const Text(
                            'Spegnerlo lo toglie dagli elenchi senza toccare i '
                            'documenti già caricati.',
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
                      onPressed:
                          (_salvando || _denominazione.text.trim().isEmpty)
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
