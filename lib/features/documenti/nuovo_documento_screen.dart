import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/contenuto_centrato.dart';
import 'documenti_screen.dart';

/// Una pagina scattata, tenuta in memoria finché non si carica.
///
/// Si tiene tutto in memoria di proposito: finché l'operatore non preme
/// "Leggi", non deve esistere niente sul server. Chi scatta una foto storta e
/// chiude l'app non deve lasciare in giro una bozza vuota.
class _Pagina {
  final Uint8List byte;
  final String nome;
  final String mime;
  const _Pagina({required this.byte, required this.nome, required this.mime});
}

enum _Fase { scelta, caricamento, lettura }

class NuovoDocumentoScreen extends ConsumerStatefulWidget {
  const NuovoDocumentoScreen({super.key});

  @override
  ConsumerState<NuovoDocumentoScreen> createState() =>
      _NuovoDocumentoScreenState();
}

class _NuovoDocumentoScreenState extends ConsumerState<NuovoDocumentoScreen> {
  final _pagine = <_Pagina>[];
  final _selettore = ImagePicker();

  _Fase _fase = _Fase.scelta;
  String _avanzamento = '';
  String? _errore;

  static const _maxPagine = 6;

  Future<void> _aggiungi({required ImageSource origine}) async {
    try {
      final scelte = origine == ImageSource.camera
          ? [
              if (await _selettore.pickImage(
                source: ImageSource.camera,
                // Abbastanza grande da leggere le cifre piccole delle
                // quantità, abbastanza piccola da caricarsi in fretta
                // sotto la copertura del magazzino.
                maxWidth: 3000,
                imageQuality: 90,
              )
                  case final XFile f)
                f
            ]
          : await _selettore.pickMultiImage(maxWidth: 3000, imageQuality: 90);

      for (final f in scelte) {
        if (_pagine.length >= _maxPagine) break;
        final byte = await f.readAsBytes();
        _pagine.add(_Pagina(
          byte: byte,
          nome: f.name,
          mime: f.mimeType ?? _mimeDa(f.name),
        ));
      }
      if (mounted) setState(() => _errore = null);
    } catch (e) {
      if (mounted) setState(() => _errore = 'Non riesco a leggere la foto: $e');
    }
  }

  Future<void> _leggi() async {
    final sessione = ref.read(sessioneProvider).valueOrNull;
    if (sessione == null || _pagine.isEmpty) return;

    setState(() {
      _fase = _Fase.caricamento;
      _errore = null;
    });

    String? documentoId;
    try {
      documentoId = await repo.creaBozza(
        organizzazioneId: sessione.organizzazioneId,
      );

      for (var i = 0; i < _pagine.length; i++) {
        setState(() => _avanzamento = 'Pagina ${i + 1} di ${_pagine.length}');
        final p = _pagine[i];
        await repo.caricaPagina(
          organizzazioneId: sessione.organizzazioneId,
          documentoId: documentoId,
          pagina: i + 1,
          byte: p.byte,
          nomeFile: p.nome,
          tipoMime: p.mime,
        );
      }

      setState(() {
        _fase = _Fase.lettura;
        _avanzamento = '';
      });

      final esito = await repo.leggiDocumento(documentoId);

      ref.invalidate(documentiProvider);
      if (!mounted) return;

      final righe = (esito['righe'] as num?)?.toInt() ?? 0;
      final automatiche = (esito['automatiche'] as num?)?.toInt() ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(righe == 0
            ? 'Nessuna riga riconosciuta: controlla che la foto sia leggibile.'
            : '$righe righe lette, $automatiche riconosciute da sole.'),
      ));

      context.go('/documenti/$documentoId');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.scelta;
        // La bozza resta: le foto sono già caricate e rileggerle costa un
        // tocco invece di rifare tutto. Se non serve, si cancella dal
        // documento.
        _errore = documentoId == null
            ? 'Non riesco a creare il documento: $e'
            : 'Le foto sono caricate ma la lettura non è riuscita.\n$e';
      });
      if (documentoId != null) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/documenti/$documentoId');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final occupato = _fase != _Fase.scelta;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuovo documento')),
      body: ContenutoCentrato(
        larghezzaMassima: 700,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (occupato) ...[
              const SizedBox(height: 40),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  _fase == _Fase.caricamento
                      ? 'Carico le foto… $_avanzamento'
                      : 'Sto leggendo il documento…',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Ci vogliono pochi secondi. Non chiudere la pagina.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ] else ...[
              const Text(
                'Fotografa il documento del fornitore: DDT o fattura. '
                'Inquadra tutto il foglio, intestazione e totali compresi.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pagine.length >= _maxPagine
                          ? null
                          : () => _aggiungi(origine: ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Scatta'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pagine.length >= _maxPagine
                          ? null
                          : () => _aggiungi(origine: ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Dalla galleria'),
                    ),
                  ),
                ],
              ),
              if (_pagine.length >= _maxPagine)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Massimo 6 pagine per documento: oltre, il modello perde '
                    'precisione sulle cifre piccole.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              if (_pagine.isEmpty)
                const _NessunaFoto()
              else
                ..._pagine.asMap().entries.map((e) => _Anteprima(
                      pagina: e.key + 1,
                      byte: e.value.byte,
                      onTogli: () => setState(() => _pagine.removeAt(e.key)),
                    )),
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
              ElevatedButton.icon(
                onPressed: _pagine.isEmpty ? null : _leggi,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_pagine.length == 1
                    ? 'Leggi il documento'
                    : 'Leggi le ${_pagine.length} pagine'),
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }
}

class _NessunaFoto extends StatelessWidget {
  const _NessunaFoto();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 44, color: AppColors.textMuted),
            SizedBox(height: 10),
            Text('Nessuna foto ancora',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _Anteprima extends StatelessWidget {
  final int pagina;
  final Uint8List byte;
  final VoidCallback onTogli;

  const _Anteprima({
    required this.pagina,
    required this.byte,
    required this.onTogli,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(byte,
                      width: 64, height: 64, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pagina $pagina',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          '${(byte.length / 1024 / 1024).toStringAsFixed(1)} MB',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Togli',
                  onPressed: onTogli,
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
}

String _mimeDa(String nome) {
  final e = nome.contains('.') ? nome.split('.').last.toLowerCase() : '';
  return switch (e) {
    'png' => 'image/png',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
