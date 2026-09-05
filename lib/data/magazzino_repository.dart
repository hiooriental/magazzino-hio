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

  // ── Cruscotto e scorte ──────────────────────────────────────────────────

  /// Tutti i numeri della prima schermata in una query sola.
  Future<Map<String, dynamic>> cruscotto(String organizzazioneId) async =>
      Map<String, dynamic>.from(
        await Db.mag
            .from('cruscotto')
            .select()
            .eq('organizzazione_id', organizzazioneId)
            .single(),
      );

  /// Lo stato di ogni ingrediente. `stati` filtra: ['esaurito','critico'].
  Future<List<Map<String, dynamic>>> statoScorte({List<String>? stati}) async {
    final q = Db.mag.from('stato_scorte').select();
    final r = stati == null || stati.isEmpty
        ? await q.order('ingrediente')
        : await q
            .inFilter('stato', stati)
            .order('giorni_copertura', ascending: true);
    return List<Map<String, dynamic>>.from(r);
  }

  Future<List<Map<String, dynamic>>> scadenze() async =>
      List<Map<String, dynamic>>.from(
        await Db.mag.from('scadenze').select().order('data_scadenza'),
      );

  Future<List<Map<String, dynamic>>> daAbbattere() async =>
      List<Map<String, dynamic>>.from(
        await Db.mag.from('da_abbattere').select().order('data_carico'),
      );

  Future<List<Map<String, dynamic>>> rincari() async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('rincari')
            .select()
            .order('variazione_percentuale', ascending: false),
      );

  Future<List<Map<String, dynamic>>> foodCost() async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('food_cost')
            .select()
            .order('incidenza_percentuale', ascending: false),
      );

  // ── Anagrafica fornitori ────────────────────────────────────────────────

  /// I fornitori con quanti documenti e quanti articoli hanno: sono i numeri
  /// che dicono chi è un fornitore vero e chi è entrato per sbaglio.
  Future<List<Map<String, dynamic>>> fornitori({bool soloAttivi = true}) async {
    final q = Db.mag.from('fornitore').select('''
          id, denominazione, partita_iva, codice_fiscale, email, telefono,
          referente, giorni_consegna, note, attivo,
          documento_carico(count), articolo_fornitore(count)
        ''');
    final r = soloAttivi
        ? await q.eq('attivo', true).order('denominazione')
        : await q.order('denominazione');
    return List<Map<String, dynamic>>.from(r);
  }

  /// Un fornitore che ha già consegnato non si cancella: cancellarlo
  /// vorrebbe dire buttare via i documenti che ha portato.
  Future<bool> haDocumenti(String fornitoreId) async {
    final r = await Db.mag
        .from('documento_carico')
        .select('id')
        .eq('fornitore_id', fornitoreId)
        .limit(1);
    return (r as List).isNotEmpty;
  }

  Future<String> creaFornitore(Map<String, dynamic> dati) async {
    final r = await Db.mag.from('fornitore').insert(dati).select('id').single();
    return r['id'] as String;
  }

  Future<void> aggiornaFornitore(String id, Map<String, dynamic> dati) async {
    await Db.mag.from('fornitore').update(dati).eq('id', id);
  }

  Future<void> eliminaFornitore(String id) async {
    await Db.mag.from('fornitore').delete().eq('id', id);
  }

  // ── Anagrafica ingredienti ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> ingredienti(
      {bool soloAttivi = true}) async {
    final q = Db.mag.from('ingrediente').select('''
          id, nome, um_base, conservazione, categoria_id, attivo,
          prodotto_internamente, vendibile_diretto, dose_standard,
          gestisci_lotti, richiede_abbattimento, giorni_scadenza_default,
          scorta_minima, scorta_ideale, costo_medio, note,
          categoria_ingrediente(nome)
        ''');
    final r = soloAttivi
        ? await q.eq('attivo', true).order('nome')
        : await q.order('nome');
    return List<Map<String, dynamic>>.from(r);
  }

  Future<Map<String, dynamic>> ingrediente(String id) async =>
      await Db.mag.from('ingrediente').select().eq('id', id).single();

  /// Cambiare l'unità base a magazzino pieno falserebbe ogni quantità già
  /// registrata: 500 g diventerebbero 500 ml senza che nessuno se ne accorga.
  /// Perciò il campo si blocca appena c'è un movimento.
  Future<bool> haMovimenti(String ingredienteId) async {
    final r = await Db.mag
        .from('movimento')
        .select('id')
        .eq('ingrediente_id', ingredienteId)
        .limit(1);
    return (r as List).isNotEmpty;
  }

  Future<String> creaIngrediente(Map<String, dynamic> dati) async {
    final r =
        await Db.mag.from('ingrediente').insert(dati).select('id').single();
    return r['id'] as String;
  }

  Future<void> aggiornaIngrediente(String id, Map<String, dynamic> dati) async {
    await Db.mag.from('ingrediente').update(dati).eq('id', id);
  }

  Future<void> aggiornaProdottoVenduto(
          String id, Map<String, dynamic> dati) async =>
      await Db.mag.from('prodotto_venduto').update(dati).eq('id', id);

  /// Si elimina solo cio' che non ha lasciato tracce.
  ///
  /// Il database rifiuta di cancellare un ingrediente che ha movimenti o che
  /// compare in una ricetta, e fa bene: cancellarlo vorrebbe dire buttare via
  /// la storia di quei movimenti. In quel caso si spegne, e sparisce dagli
  /// elenchi senza portarsi dietro niente.
  Future<void> eliminaIngrediente(String id) async {
    await Db.mag.from('ingrediente').delete().eq('id', id);
  }

  Future<void> eliminaProdottoVenduto(String id) async {
    await Db.mag.from('prodotto_venduto').delete().eq('id', id);
  }

  // ── Ricette ─────────────────────────────────────────────────────────────

  /// I prodotti a menù, con l'indicazione se hanno già una ricetta attiva.
  Future<List<Map<String, dynamic>>> prodottiVenduti() async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('prodotto_venduto')
            .select('id, nome, categoria_menu, prezzo_vendita, '
                'senza_distinta, codice_esterno, distinta(id, stato)')
            .eq('attivo', true)
            .order('nome'),
      );

  /// I semilavorati: ingredienti che si producono invece di comprarli.
  Future<List<Map<String, dynamic>>> semilavorati() async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('ingrediente')
            .select('id, nome, um_base, costo_medio, distinta(id, stato)')
            .eq('prodotto_internamente', true)
            .eq('attivo', true)
            .order('nome'),
      );

  Future<String> creaProdottoVenduto({
    required String organizzazioneId,
    required String nome,
    String? codiceEsterno,
    String? categoria,
    num? prezzo,
  }) async {
    final r = await Db.mag
        .from('prodotto_venduto')
        .insert({
          'organizzazione_id': organizzazioneId,
          'nome': nome,
          if (codiceEsterno != null && codiceEsterno.isNotEmpty)
            'codice_esterno': codiceEsterno,
          if (categoria != null && categoria.isNotEmpty)
            'categoria_menu': categoria,
          if (prezzo != null) 'prezzo_vendita': prezzo,
        })
        .select('id')
        .single();
    return r['id'] as String;
  }

  /// Crea la ricetta se non c'è, e restituisce quella attiva.
  ///
  /// Nasce già attiva: una ricetta in bozza che nessuno attiva è una ricetta
  /// che non scarica niente, e il difetto si scoprirebbe solo a inventario.
  Future<String> distintaAttiva({
    required String organizzazioneId,
    String? prodottoVendutoId,
    String? ingredienteId,
    num? quantitaProdotta,
  }) async {
    final q = Db.mag.from('distinta').select('id').eq('stato', 'attiva');
    final esistente = await (prodottoVendutoId != null
            ? q.eq('prodotto_venduto_id', prodottoVendutoId)
            : q.eq('ingrediente_id', ingredienteId!))
        .maybeSingle();

    if (esistente != null) return esistente['id'] as String;

    final r = await Db.mag
        .from('distinta')
        .insert({
          'organizzazione_id': organizzazioneId,
          if (prodottoVendutoId != null)
            'prodotto_venduto_id': prodottoVendutoId,
          if (ingredienteId != null) 'ingrediente_id': ingredienteId,
          if (quantitaProdotta != null) 'quantita_prodotta': quantitaProdotta,
          'stato': 'attiva',
        })
        .select('id')
        .single();
    return r['id'] as String;
  }

  /// L'id della ricetta attiva di un semilavorato, se ce l'ha.
  ///
  /// Diversa da `distintaAttiva`, che se non c'è la crea: qui serve solo
  /// sapere se esiste, senza fabbricarne una per il solo fatto di aver
  /// guardato.
  Future<String?> distintaDiIngrediente(String ingredienteId) async {
    final r = await Db.mag
        .from('distinta')
        .select('id')
        .eq('ingrediente_id', ingredienteId)
        .eq('stato', 'attiva')
        .maybeSingle();
    return r?['id'] as String?;
  }

  Future<Map<String, dynamic>> distinta(String id) async =>
      await Db.mag.from('distinta').select('''
            id, stato, versione, valida_da, quantita_prodotta, variabile, note,
            prodotto_venduto_id, ingrediente_id,
            prodotto_venduto(id, nome, prezzo_vendita, categoria_menu,
                             codice_esterno, senza_distinta, attivo,
                             descrizione),
            ingrediente(id, nome, um_base, conservazione, categoria_id, attivo,
                        prodotto_internamente, vendibile_diretto, dose_standard,
                        gestisci_lotti, richiede_abbattimento,
                        giorni_scadenza_default, scorta_minima, scorta_ideale,
                        note)
          ''').eq('id', id).single();

  Future<List<Map<String, dynamic>>> componenti(String distintaId) async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('distinta_componente')
            .select('id, quantita, scarto_percentuale, ordinamento, '
                'ingrediente_id, ingrediente(nome, um_base, costo_medio)')
            .eq('distinta_id', distintaId)
            .order('ordinamento')
            .order('id'),
      );

  Future<void> aggiungiComponente({
    required String distintaId,
    required String ingredienteId,
    required num quantita,
    num scarto = 0,
  }) async {
    await Db.mag.from('distinta_componente').insert({
      'distinta_id': distintaId,
      'ingrediente_id': ingredienteId,
      'quantita': quantita,
      'scarto_percentuale': scarto,
    });
  }

  Future<void> aggiornaComponente(String id,
      {num? quantita, num? scarto}) async {
    await Db.mag.from('distinta_componente').update({
      if (quantita != null) 'quantita': quantita,
      if (scarto != null) 'scarto_percentuale': scarto,
    }).eq('id', id);
  }

  Future<void> impostaResa(String distintaId, num quantitaProdotta) async {
    await Db.mag
        .from('distinta')
        .update({'quantita_prodotta': quantitaProdotta}).eq('id', distintaId);
  }

  Future<num?> costoDistinta(String distintaId) async =>
      await Db.mag.rpc('costo_distinta', params: {'p_distinta_id': distintaId})
          as num?;

  // ── Abbattimento ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> registraAbbattimento({
    required String lottoId,
    required DateTime inizio,
    required DateTime fine,
    required num temperatura,
  }) async =>
      Map<String, dynamic>.from(
        await Db.mag.rpc('registra_abbattimento', params: {
          'p_lotto_id': lottoId,
          'p_inizio': inizio.toUtc().toIso8601String(),
          'p_fine': fine.toUtc().toIso8601String(),
          'p_temperatura': temperatura,
        }),
      );

  // ── Lavorazioni ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> lavorazioni({int limite = 40}) async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('resa_lavorazione')
            .select()
            .order('data_lavorazione', ascending: false)
            .limit(limite),
      );

  Future<Map<String, dynamic>> lavorazione(String id) async =>
      await Db.mag.from('lavorazione').select().eq('id', id).single();

  Future<List<Map<String, dynamic>>> lavorazioneInput(String id) async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('lavorazione_input')
            .select('id, quantita, costo_unitario, ingrediente_id, '
                'ingrediente(nome, um_base, costo_medio)')
            .eq('lavorazione_id', id),
      );

  Future<List<Map<String, dynamic>>> lavorazioneOutput(String id) async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('lavorazione_output')
            .select('id, quantita, valore_relativo, costo_unitario, '
                'ingrediente_id, ingrediente(nome, um_base)')
            .eq('lavorazione_id', id),
      );

  Future<String> creaLavorazione({
    required String organizzazioneId,
    required String tipo,
    String ripartizione = 'valore',
  }) async {
    final r = await Db.mag
        .from('lavorazione')
        .insert({
          'organizzazione_id': organizzazioneId,
          'tipo': tipo,
          'ripartizione': ripartizione,
        })
        .select('id')
        .single();
    return r['id'] as String;
  }

  /// I lotti di questo ingrediente che hanno ancora merce dentro.
  ///
  /// Servono a sapere DA QUALE pezzo si sta tagliando: è l'unico modo perché
  /// i tranci ricordino da quale tonno vengono, e la tracciabilità non si
  /// spezzi proprio nel punto in cui il pesce viene trasformato.
  Future<List<Map<String, dynamic>>> lottiDisponibili(
          String ingredienteId) async =>
      List<Map<String, dynamic>>.from(
        await Db.mag
            .from('giacenza_lotto')
            .select('lotto_id, lotto, data_scadenza, quantita, abbattuto')
            .eq('ingrediente_id', ingredienteId)
            .gt('quantita', 0)
            .order('data_scadenza', nullsFirst: false),
      );

  Future<void> aggiungiInput(
    String lavorazioneId,
    String ingredienteId,
    num quantita, {
    String? lottoId,
  }) async {
    await Db.mag.from('lavorazione_input').insert({
      'lavorazione_id': lavorazioneId,
      'ingrediente_id': ingredienteId,
      'quantita': quantita,
      if (lottoId != null) 'lotto_id': lottoId,
    });
  }

  Future<void> aggiungiOutput(String lavorazioneId, String ingredienteId,
      num quantita, num valoreRelativo) async {
    await Db.mag.from('lavorazione_output').insert({
      'lavorazione_id': lavorazioneId,
      'ingrediente_id': ingredienteId,
      'quantita': quantita,
      'valore_relativo': valoreRelativo,
    });
  }

  Future<void> togliRiga(String tabella, String id) async {
    await Db.mag.from(tabella).delete().eq('id', id);
  }

  Future<Map<String, dynamic>> chiudiLavorazione(String id) async =>
      Map<String, dynamic>.from(
        await Db.mag
            .rpc('chiudi_lavorazione', params: {'p_lavorazione_id': id}),
      );

  // ── Azioni ──────────────────────────────────────────────────────────────
  //
  // Sono tutte funzioni del database, non sequenze di chiamate dall'app.
  // Un abbinamento tocca articolo, alias e righe; una conferma tocca
  // movimenti, lotti, prezzi e costo medio. Se la connessione cade a meta',
  // deve non essere successo niente — e questo lo garantisce solo una
  // transazione lato server.

  Future<Map<String, dynamic>> creaFornitoreDaDocumento(
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
