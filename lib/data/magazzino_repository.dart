import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../core/db.dart';

/// Tutte le chiamate al database del magazzino passano da qui.
///
/// In restaurant-booking convivono due modi di leggere i dati — modelli
/// tipizzati e mappe grezze sparse nelle schermate — e il CLAUDE.md avverte di
/// non mescolarli. Qui ce n'e' uno solo. Con quantita' e costi in ballo, una
/// query scritta a mano dentro una schermata e' il modo piu' rapido per
/// scoprire fra tre mesi che un numero e' sbagliato senza sapere dove.
class MagazzinoRepository {
  const MagazzinoRepository();

  // ── Lettura ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> documento(String id) async =>
      await Db.mag.from('documento_carico').select('''
            id, numero_documento, data_documento, data_consegna, stato, tipo,
            origine, totale_dichiarato, totale_documento, totale_calcolato,
            note, fornitore_id, fornitore_letto,
            fornitore(id, denominazione, partita_iva)
          ''').eq('id', id).single();

  Future<List<Map<String, dynamic>>> righe(String documentoId) async =>
      List<Map<String, dynamic>>.from(
        await Db.mag.from('documento_carico_riga').select('''
              id, numero_riga, descrizione_originale, codice_fornitore_originale,
              um_dichiarata, quantita_testo, prezzo_testo, totale_testo,
              quantita_dichiarata, prezzo_unitario, totale_riga,
              quantita_base, costo_unitario_base, fattore_conversione_applicato,
              stato_match, metodo_match, confidenza, note,
              ingrediente_id, ingrediente(nome, um_base)
            ''').eq('documento_id', documentoId).order('numero_riga'),
      );

  /// Cerca fra gli ingredienti gia' in anagrafica.
  Future<List<Map<String, dynamic>>> cercaIngredienti(String testo) async {
    final q =
        Db.mag.from('ingrediente').select('id, nome, um_base, costo_medio');
    final risultato = testo.trim().isEmpty
        ? await q.eq('attivo', true).order('nome').limit(30)
        : await q
            .eq('attivo', true)
            .ilike('nome', '%${testo.trim()}%')
            .order('nome')
            .limit(30);
    return List<Map<String, dynamic>>.from(risultato);
  }

  /// I candidati che il motore di riconoscimento propone per una descrizione:
  /// serve a mostrare all'operatore *perche'* una riga e' rimasta indietro.
  Future<List<Map<String, dynamic>>> candidati({
    required String organizzazioneId,
    String? fornitoreId,
    required String descrizione,
    String? codice,
  }) async =>
      List<Map<String, dynamic>>.from(
        await Db.mag.rpc('cerca_articolo', params: {
          'p_organizzazione_id': organizzazioneId,
          'p_fornitore_id': fornitoreId,
          'p_descrizione': descrizione,
          'p_codice': codice,
          'p_limite': 5,
        }),
      );

  /// Il database sa già convertire questa unità? `null` significa no, e
  /// allora il fattore va chiesto all'operatore.
  ///
  /// La domanda si gira a `converti_um` invece di riscrivere la regola qui:
  /// è la stessa funzione che usa il riconoscimento, e due copie della stessa
  /// regola prima o poi divergono.
  Future<num?> fattoreAutomatico(String? um, String umBase) async =>
      await Db.mag.rpc('converti_um', params: {
        'p_um': um,
        'p_um_base': umBase,
      }) as num?;

  Future<List<Map<String, dynamic>>> categorie() async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('categoria_ingrediente')
            .select('id, nome')
            .order('ordinamento'),
      );

  // ── Azioni ──────────────────────────────────────────────────────────────
  //
  // Sono tutte funzioni del database, non sequenze di chiamate dall'app.
  // Un abbinamento tocca articolo, alias e righe; una conferma tocca
  // movimenti, lotti, prezzi e costo medio. Se la connessione cade a meta',
  // deve non essere successo niente — e questo lo garantisce solo una
  // transazione lato server.

  Future<Map<String, dynamic>> creaFornitore(
    String documentoId, {
    String? denominazione,
    String? partitaIva,
  }) async =>
      Map<String, dynamic>.from(
        await Db.mag.rpc('crea_fornitore_da_documento', params: {
          'p_documento_id': documentoId,
          'p_denominazione': denominazione,
          'p_partita_iva': partitaIva,
        }),
      );

  Future<Map<String, dynamic>> abbina({
    required String rigaId,
    required String ingredienteId,
    num? fattoreConversione,
  }) async =>
      Map<String, dynamic>.from(
        await Db.mag.rpc('abbina_riga', params: {
          'p_riga_id': rigaId,
          'p_ingrediente_id': ingredienteId,
          'p_fattore_conversione': fattoreConversione,
        }),
      );

  Future<Map<String, dynamic>> creaIngredienteEAbbina({
    required String rigaId,
    required String nome,
    required String umBase,
    num? fattoreConversione,
    String? categoriaId,
    String conservazione = 'ambiente',
    bool gestisciLotti = false,
    bool richiedeAbbattimento = false,
  }) async =>
      Map<String, dynamic>.from(
        await Db.mag.rpc('crea_ingrediente_da_riga', params: {
          'p_riga_id': rigaId,
          'p_nome': nome,
          'p_um_base': umBase,
          'p_fattore_conversione': fattoreConversione,
          'p_categoria_id': categoriaId,
          'p_conservazione': conservazione,
          'p_gestisci_lotti': gestisciLotti,
          'p_richiede_abbattimento': richiedeAbbattimento,
        }),
      );

  Future<Map<String, dynamic>> conferma(String documentoId) async =>
      Map<String, dynamic>.from(
        await Db.mag
            .rpc('conferma_carico', params: {'p_documento_id': documentoId}),
      );

  Future<Map<String, dynamic>> storna(
          String documentoId, String? motivo) async =>
      Map<String, dynamic>.from(
        await Db.mag.rpc('storna_carico',
            params: {'p_documento_id': documentoId, 'p_motivo': motivo}),
      );

  // ── Creazione di un documento dalle foto ────────────────────────────────

  /// Crea la bozza vuota. Le foto e la lettura arrivano dopo.
  Future<String> creaBozza({
    required String organizzazioneId,
    String tipo = 'ddt',
  }) async {
    final oggi = DateTime.now();
    final data =
        '${oggi.year}-${oggi.month.toString().padLeft(2, '0')}-${oggi.day.toString().padLeft(2, '0')}';

    final riga = await Db.mag
        .from('documento_carico')
        .insert({
          'organizzazione_id': organizzazioneId,
          'tipo': tipo,
          'origine': 'foto',
          'data_documento': data,
          'data_consegna': data,
          'stato': 'bozza',
        })
        .select('id')
        .single();

    return riga['id'] as String;
  }

  /// Carica una pagina su Storage e la registra come allegato.
  ///
  /// Il percorso lo costruisce il database con `percorso_allegato()`: la
  /// stessa funzione che conosce la convenzione usata dalle policy. Se la
  /// costruissimo qui, il giorno che cambia lo schema delle cartelle
  /// avremmo due posti da aggiornare e ne aggiorneremmo uno.
  Future<void> caricaPagina({
    required String organizzazioneId,
    required String documentoId,
    required int pagina,
    required Uint8List byte,
    required String nomeFile,
    required String tipoMime,
  }) async {
    final estensione =
        nomeFile.contains('.') ? nomeFile.split('.').last.toLowerCase() : 'jpg';

    final percorso = await Db.mag.rpc('percorso_allegato', params: {
      'p_organizzazione_id': organizzazioneId,
      'p_documento_id': documentoId,
      'p_pagina': pagina,
      'p_estensione': estensione,
    }) as String;

    await Db.client.storage.from('documenti-magazzino').uploadBinary(
          percorso,
          byte,
          fileOptions: FileOptions(contentType: tipoMime, upsert: true),
        );

    await Db.mag.from('allegato').insert({
      'organizzazione_id': organizzazioneId,
      'documento_id': documentoId,
      'percorso_storage': percorso,
      'nome_file': nomeFile,
      'tipo_mime': tipoMime,
      'dimensione_byte': byte.length,
      // Impronta del file: serve a riconoscere la stessa foto caricata due
      // volte, e a dimostrare che l'immagine su cui ha lavorato il modello
      // è esattamente quella archiviata.
      'hash_sha256': sha256.convert(byte).toString(),
      'pagina': pagina,
    });
  }

  /// Chiama la edge function che legge le foto.
  Future<Map<String, dynamic>> leggiDocumento(String documentoId) async {
    final risposta = await Db.client.functions.invoke(
      'estrai-ddt',
      body: {'documento_id': documentoId},
    );

    final corpo = risposta.data;
    if (risposta.status != 200) {
      final messaggio = corpo is Map ? corpo['error'] : corpo;
      throw Exception(
          messaggio ?? 'Lettura non riuscita (${risposta.status}).');
    }
    return Map<String, dynamic>.from(corpo as Map);
  }

  /// Elimina un documento non confermato, con le sue foto.
  ///
  /// Prima la riga, poi i file: se saltasse l'ordine e la cancellazione della
  /// riga fallisse, resterebbe un documento che punta a foto sparite. Al
  /// contrario, un file orfano su Storage non fa danno a nessuno.
  ///
  /// Sui documenti confermati non serve controllare qui: c'è un trigger nel
  /// database, ed è quello il posto giusto perché vale anche per chi non
  /// passa da questa app.
  Future<void> elimina(String documentoId) async {
    final allegati = await Db.mag
        .from('allegato')
        .select('percorso_storage')
        .eq('documento_id', documentoId);

    final percorsi = List<Map<String, dynamic>>.from(allegati)
        .map((a) => a['percorso_storage'] as String)
        .toList();

    await Db.mag.from('documento_carico').delete().eq('id', documentoId);

    if (percorsi.isNotEmpty) {
      try {
        await Db.client.storage.from('documenti-magazzino').remove(percorsi);
      } catch (_) {
        // File orfani: fastidiosi, non dannosi. Non vale la pena far
        // fallire un'operazione già andata a buon fine.
      }
    }
  }

  /// Il peso davvero pesato al banco. Prevale sulla quantita' del documento.
  Future<void> registraPesata(String rigaId, num quantitaReale) async {
    await Db.mag.from('documento_carico_riga').update({
      'quantita_reale': quantitaReale,
      'pesata_da': Db.utente!.id,
      'pesata_il': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', rigaId);
  }
}

const repo = MagazzinoRepository();
