import 'package:flutter/material.dart';

import '../../data/magazzino_repository.dart';
import '../theme/app_theme.dart';

/// Sceglie un ingrediente dall'anagrafica.
///
/// Restituisce la mappa dell'ingrediente, o `null` se si annulla. Serve in
/// più punti — lavorazioni, ricette, inventari — e ripeterlo ogni volta
/// significherebbe tre ricerche che si comportano in tre modi diversi.
Future<Map<String, dynamic>?> scegliIngrediente(
  BuildContext context, {
  String titolo = 'Scegli un ingrediente',
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _Dialogo(titolo: titolo),
    );

class _Dialogo extends StatefulWidget {
  final String titolo;
  const _Dialogo({required this.titolo});

  @override
  State<_Dialogo> createState() => _DialogoState();
}

class _DialogoState extends State<_Dialogo> {
  final _ricerca = TextEditingController();
  List<Map<String, dynamic>> _risultati = const [];
  bool _caricando = true;

  @override
  void initState() {
    super.initState();
    _cerca();
  }

  @override
  void dispose() {
    _ricerca.dispose();
    super.dispose();
  }

  Future<void> _cerca() async {
    setState(() => _caricando = true);
    final r = await repo.cercaIngredienti(_ricerca.text);
    if (mounted) {
      setState(() {
        _risultati = r;
        _caricando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.titolo),
        content: SizedBox(
          width: 420,
          height: 440,
          child: Column(
            children: [
              TextField(
                controller: _ricerca,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Cerca',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => _cerca(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _caricando
                    ? const Center(child: CircularProgressIndicator())
                    : _risultati.isEmpty
                        ? const Center(
                            child: Text('Nessun ingrediente trovato.',
                                style:
                                    TextStyle(color: AppColors.textSecondary)))
                        : ListView.builder(
                            itemCount: _risultati.length,
                            itemBuilder: (_, i) {
                              final x = _risultati[i];
                              return ListTile(
                                dense: true,
                                title: Text(x['nome'] as String),
                                subtitle: Text('in ${x['um_base']}',
                                    style: const TextStyle(fontSize: 12)),
                                onTap: () => Navigator.pop(context, x),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
        ],
      );
}

/// Chiede da quale lotto si sta prelevando.
///
/// Restituisce l'id del lotto, oppure `null` se non ce ne sono o se
/// l'operatore sceglie di non indicarlo. Con un lotto solo non chiede niente:
/// non ha senso far scegliere fra una cosa sola.
///
/// I lotti sono ordinati per scadenza: il primo della lista è quello che
/// andrebbe consumato per primo.
Future<String?> scegliLotto(
  BuildContext context,
  String ingredienteId,
  String nomeIngrediente,
) async {
  final lotti = await repo.lottiDisponibili(ingredienteId);
  if (lotti.isEmpty) return null;
  if (lotti.length == 1) return lotti.first['lotto_id'] as String?;
  if (!context.mounted) return null;

  return showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text('Da quale lotto di $nomeIngrediente?'),
      children: [
        ...lotti.map((l) => SimpleDialogOption(
              onPressed: () => Navigator.pop(c, l['lotto_id'] as String),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l['lotto'] as String? ?? ''),
                subtitle: Text([
                  '${l['quantita']} disponibili',
                  if (l['data_scadenza'] != null)
                    'scade il ${l['data_scadenza']}',
                  if (l['abbattuto'] == false) 'non abbattuto',
                ].join(' · ')),
              ),
            )),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c),
          child: const Text('Non lo so',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    ),
  );
}

/// Chiede un numero: un peso, una quantità.
Future<num?> chiediNumero(
  BuildContext context, {
  required String titolo,
  required String etichetta,
  String? aiuto,
  num? iniziale,
}) async {
  final c = TextEditingController(
      text: iniziale == null ? '' : iniziale.toString().replaceAll('.', ','));
  final v = await showDialog<num>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titolo),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: etichetta, helperText: aiuto),
        onSubmitted: (t) =>
            Navigator.pop(ctx, num.tryParse(t.replaceAll(',', '.'))),
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
