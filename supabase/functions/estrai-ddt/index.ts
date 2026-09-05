// ============================================================================
//  estrai-ddt — dalle foto di un DDT alle righe del documento
// ============================================================================
//
//  Riceve l'id di un documento gia' creato in bozza, con le sue foto gia'
//  caricate su Storage. Legge le immagini, le manda al modello, ne ricava
//  righe strutturate, le scrive, e poi chiama il riconoscimento articoli.
//
//  Cosa NON fa, di proposito:
//    - non conferma il carico: quello lo fa una persona, e solo un gestore
//    - non crea fornitori o ingredienti nuovi: propone, non decide
//    - non interpreta le unita' di misura: le copia com'erano scritte, ed e'
//      `risolvi_documento` a convertirle con le regole deterministiche
//
//  Il modello serve a leggere, non a calcolare. Ogni numero che conta passa
//  dopo per il database, dove i conti si possono verificare.
//
//  Verso OpenAI escono: le immagini dei DDT (tramite URL firmato che scade in
//  10 minuti) e nient'altro. Nessun dato di magazzino, nessun prezzo storico,
//  nessuna anagrafica.
// ============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

// Versione del prompt: finisce in `estrazione_ai` insieme alla risposta.
// Quando fra sei mesi un carico risultera' sbagliato, serve a sapere con
// quali istruzioni era stato letto.
const VERSIONE_PROMPT = 'ddt-2026-09-04';

// Vision su documenti fotografati storti: gpt-4o-mini sbaglia troppo sui
// numeri piccoli. Sovrascrivibile col segreto OPENAI_MODEL_VISION.
const MODELLO = (Deno.env.get('OPENAI_MODEL_VISION') ?? '').trim() || 'gpt-4o';

// Oltre questo il payload diventa pesante e il modello perde attenzione.
const MAX_PAGINE = 6;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function risposta(corpo: unknown, stato = 200) {
  return new Response(JSON.stringify(corpo), {
    status: stato,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

// ── Cosa deve tornare il modello ────────────────────────────────────────────
//
// Schema stretto: OpenAI rifiuta la risposta se non combacia, invece di
// restituire un JSON plausibile ma diverso ogni volta. Tutti i campi sono
// obbligatori e annullabili: "non lo so" e' una risposta legittima e va
// distinta da un valore inventato.
const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['fornitore', 'documento', 'righe'],
  properties: {
    fornitore: {
      type: 'object',
      additionalProperties: false,
      required: ['denominazione', 'partita_iva'],
      properties: {
        denominazione: { type: ['string', 'null'] },
        partita_iva: { type: ['string', 'null'] },
      },
    },
    documento: {
      type: 'object',
      additionalProperties: false,
      required: ['numero', 'data', 'tipo', 'totale_imponibile_testo', 'totale_documento_testo'],
      properties: {
        numero: { type: ['string', 'null'] },
        data: { type: ['string', 'null'], description: 'AAAA-MM-GG' },
        tipo: { type: ['string', 'null'], enum: ['ddt', 'fattura', 'reso', null] },
        // Due totali distinti, e servono entrambi. Il confronto con la somma
        // delle righe ha senso solo sull'imponibile: le righe sono al netto,
        // il totale documento e' IVA compresa. Confrontarli vorrebbe dire
        // segnalare uno scostamento del 22% a ogni documento, cioe' spegnere
        // il controllo dopo due settimane.
        // Trascritti come stringhe, come tutti gli altri numeri.
        totale_imponibile_testo: { type: ['string', 'null'] },
        totale_documento_testo: { type: ['string', 'null'] },
      },
    },
    righe: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'descrizione', 'codice', 'unita_misura',
          'quantita_testo', 'prezzo_testo', 'totale_testo',
          'sconto_percentuale', 'lotto', 'scadenza',
        ],
        properties: {
          descrizione: { type: 'string' },
          codice: { type: ['string', 'null'] },
          unita_misura: { type: ['string', 'null'] },

          // I numeri si chiedono come STRINGHE, trascritte com'erano stampate.
          // La conversione la fa magazzino.numero_it_da_testo(), con regole
          // fisse. Motivo, dal collaudo su un DDT vero: lo stesso modello ha
          // letto la stessa riga in due modi diversi in due tentativi, e la
          // seconda volta ha cambiato quantita' E prezzo insieme in modo che
          // il totale tornasse lo stesso. Un errore coerente supera qualunque
          // controllo aritmetico. Trascrivere caratteri e' cio' che sa fare
          // bene; decidere se un punto separa migliaia o decimali no.
          quantita_testo: { type: ['string', 'null'] },
          prezzo_testo: { type: ['string', 'null'] },
          totale_testo: { type: ['string', 'null'] },

          sconto_percentuale: { type: ['number', 'null'] },
          lotto: { type: ['string', 'null'] },
          scadenza: { type: ['string', 'null'], description: 'AAAA-MM-GG' },
        },
      },
    },
  },
};

const ISTRUZIONI = `Leggi questo documento di trasporto o fattura di un fornitore italiano di ristorazione ed estrai i dati.

REGOLE, in ordine di importanza:

1. Trascrivi, non interpretare. La descrizione dell'articolo va copiata ESATTAMENTE come e' stampata, comprese abbreviazioni, punti e barre: "MOZZ. FDL 4X2,5" resta "MOZZ. FDL 4X2,5". Non espandere, non correggere, non tradurre.

2. Non convertire le unita' di misura. Se c'e' scritto CT scrivi CT, se c'e' KG scrivi KG. La conversione la fa un altro sistema.

2bis. IL CODICE e' quello con cui IL FORNITORE identifica il suo articolo:
   colonne "Codice", "Cod. art.", "Articolo", "Rif.", "Vs. codice".
   NON e' il codice doganale, che sui documenti esteri compare spesso accanto
   alla riga: 8 cifre, etichettato "N.C.", "Nomenclatura", "Cod. doganale",
   "HS Code", "Tariffa", oppure senza etichetta. Quello identifica una
   CATEGORIA merceologica, non un prodotto: prodotti diversi lo condividono.
   Riconoscerlo e' facile: se lo stesso numero compare su righe con prodotti
   diversi, o se e' di 8 cifre senza lettere e senza separatori, e' doganale.
   In caso di dubbio metti null: un codice mancante costa un tocco
   all'operatore, un codice sbagliato abbina in automatico il prodotto errato.

3. NUMERI — non convertirli, TRASCRIVILI.
   Per quantita', prezzo unitario e totale di riga restituisci la stringa
   esattamente come e' stampata sul documento, carattere per carattere,
   con i suoi punti e le sue virgole:
     quantita_testo: "720.000,00"
     prezzo_testo:   "0,007"
     totale_testo:   "5.040,00"
   Non togliere separatori, non aggiungere zeri, non arrotondare, non
   convertire in notazione inglese. La conversione la fa un altro sistema.
   Se un numero e' illeggibile metti null: e' molto meglio di una stringa
   ricostruita a intuito.

4. NON AGGIUSTARE MAI UN NUMERO PERCHE' I CONTI TORNINO.
   Se quantita' per prezzo non da' il totale stampato, trascrivi comunque i
   tre valori come sono. Non e' un tuo problema da risolvere: il controllo lo
   fa un altro sistema, che ha bisogno di vedere l'incoerenza per segnalarla.
   Cambiare una cifra per rendere coerente la riga trasforma un errore
   visibile in un errore invisibile, ed e' il danno peggiore che puoi fare.

5. Se un dato non si legge o non c'e', metti null. Non stimare, non dedurre,
   non completare. Un valore inventato e' molto peggio di un valore mancante,
   perche' nessuno lo controllera'.

6. I DUE TOTALI sono cose diverse, e vanno trascritti come stringhe anche loro.
   Stanno nel riquadro dei totali, di solito in basso o sul retro.
   - totale_imponibile_testo: il totale al netto dell'IVA. Sui documenti
     italiani si chiama "Imponibile", "Totale imponibile", "Totale merce",
     "Totale netto". E' quello che deve corrispondere alla somma delle righe.
   - totale_documento_testo: il totale finale da pagare, IVA compresa.
     "Totale documento", "Totale fattura", "Netto a pagare".
   Cercali entrambi. Se il riquadro dei totali non e' visibile nella foto, o
   il documento non riporta prezzi, metti null.

7. Includi solo le righe di merce. Salta trasporto, imballi, contributi,
   arrotondamenti, sconti in calce, totali e riepiloghi IVA.

8. L'intestazione contiene il fornitore, cioe' CHI EMETTE il documento: di
   solito in alto a sinistra o nel logo. Non confonderlo col destinatario
   ("Spett.le", "Destinatario", "Luogo di consegna"), che e' il ristorante.
   Se l'intestazione e' tagliata o illeggibile, metti null.

9. Se lo stesso articolo compare su piu' righe, tienile separate: possono
   avere lotti o prezzi diversi.

10. Le pagine sono di un unico documento, in ordine. Non ripetere le righe che
    compaiono su piu' pagine per continuazione.`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return risposta({ error: 'Usare POST.' }, 405);

  const inizio = Date.now();

  const autorizzazione = req.headers.get('Authorization');
  if (!autorizzazione) return risposta({ error: 'Manca il token di accesso.' }, 401);

  const chiave = Deno.env.get('OPENAI_API_KEY');
  if (!chiave) {
    return risposta({ error: 'Manca OPENAI_API_KEY nei segreti di Supabase.' }, 500);
  }

  // Client con il token di chi chiama: tutte le regole di sicurezza del
  // database valgono anche qui dentro. Nessuna scorciatoia con service_role.
  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: autorizzazione } } },
  );
  const mag = db.schema('magazzino');

  let documentoId: string | null = null;
  let organizzazioneId: string | null = null;

  try {
    const corpo = await req.json().catch(() => ({}));
    documentoId = corpo.documento_id ?? null;
    const forza = corpo.forza === true;

    if (!documentoId) return risposta({ error: 'Manca documento_id.' }, 400);

    // ── Il documento ────────────────────────────────────────────────────
    const { data: doc, error: errDoc } = await mag
      .from('documento_carico')
      .select('id, organizzazione_id, stato, fornitore_id')
      .eq('id', documentoId)
      .maybeSingle();

    if (errDoc) throw new Error(`Lettura documento: ${errDoc.message}`);
    if (!doc) return risposta({ error: 'Documento inesistente o non visibile.' }, 404);
    organizzazioneId = doc.organizzazione_id;

    if (doc.stato === 'confermato' || doc.stato === 'annullato') {
      return risposta({ error: `Documento gia' ${doc.stato}: non si rilegge.` }, 409);
    }

    // ── Righe gia' presenti ─────────────────────────────────────────────
    // Rileggere una foto e' un'operazione che si rifa' volentieri quando la
    // prima lettura e' venuta male. Ma non deve poter cancellare il lavoro
    // che qualcuno ha gia' fatto a mano.
    const { data: esistenti } = await mag
      .from('documento_carico_riga')
      .select('id, stato_match')
      .eq('documento_id', documentoId);

    if (esistenti && esistenti.length > 0) {
      if (!forza) {
        return risposta({
          error: 'Il documento ha gia\' delle righe. Richiamare con forza: true per rileggerlo.',
          righe_presenti: esistenti.length,
        }, 409);
      }
      const daTogliere = esistenti
        .filter((r) => r.stato_match !== 'confermato')
        .map((r) => r.id);
      if (daTogliere.length > 0) {
        await mag.from('documento_carico_riga').delete().in('id', daTogliere);
      }
    }

    // ── Le foto ─────────────────────────────────────────────────────────
    const { data: allegati, error: errAll } = await mag
      .from('allegato')
      .select('percorso_storage, pagina, tipo_mime')
      .eq('documento_id', documentoId)
      .order('pagina');

    if (errAll) throw new Error(`Lettura allegati: ${errAll.message}`);
    if (!allegati || allegati.length === 0) {
      return risposta({ error: 'Il documento non ha immagini da leggere.' }, 400);
    }

    const immagini = allegati.filter((a) => (a.tipo_mime ?? '').startsWith('image/'));
    if (immagini.length === 0) {
      return risposta({ error: 'Nessuna immagine: per gli XML si usa un altro percorso.' }, 400);
    }
    if (immagini.length > MAX_PAGINE) {
      return risposta({
        error: `Troppe pagine (${immagini.length}). Massimo ${MAX_PAGINE} per lettura.`,
      }, 400);
    }

    // URL firmati invece delle immagini codificate: il payload resta leggero
    // e il link scade da solo dopo dieci minuti.
    const urlImmagini: string[] = [];
    for (const img of immagini) {
      const { data: firmato, error: errUrl } = await db.storage
        .from('documenti-magazzino')
        .createSignedUrl(img.percorso_storage, 600);
      if (errUrl || !firmato) {
        throw new Error(`Immagine non accessibile (pagina ${img.pagina}): ${errUrl?.message}`);
      }
      urlImmagini.push(firmato.signedUrl);
    }

    // ── La lettura ──────────────────────────────────────────────────────
    // detail: 'high' e' necessario sui documenti: in bassa risoluzione le
    // cifre piccole delle quantita' diventano indistinguibili.
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${chiave}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODELLO,
        temperature: 0,
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: ISTRUZIONI },
            ...urlImmagini.map((url) => ({
              type: 'image_url',
              image_url: { url, detail: 'high' },
            })),
          ],
        }],
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'documento_fornitore', strict: true, schema: SCHEMA },
        },
      }),
    });

    if (!res.ok) {
      const testo = await res.text();
      throw new Error(
        `OpenAI ha rifiutato la richiesta (${res.status}) col modello "${MODELLO}". `
        + testo.slice(0, 300),
      );
    }

    const risultato = await res.json();
    const grezzo = risultato.choices?.[0]?.message?.content;
    if (!grezzo) throw new Error('Risposta di OpenAI vuota.');

    const letto = JSON.parse(grezzo);
    const durata = Date.now() - inizio;

    // ── La scatola nera ─────────────────────────────────────────────────
    // Scritta prima di toccare qualunque riga: se l'inserimento fallisse,
    // resterebbe comunque la prova di cosa aveva risposto il modello.
    await mag.from('estrazione_ai').insert({
      organizzazione_id: organizzazioneId,
      documento_id: documentoId,
      modello: MODELLO,
      versione_prompt: VERSIONE_PROMPT,
      stato: 'completata',
      payload: letto,
      token_input: risultato.usage?.prompt_tokens ?? null,
      token_output: risultato.usage?.completion_tokens ?? null,
      durata_ms: durata,
    });

    // ── Testata ─────────────────────────────────────────────────────────
    // Il fornitore si aggancia solo se esiste gia' e non ci sono dubbi.
    // Crearlo automaticamente riempirebbe l'anagrafica di doppioni scritti
    // in modo leggermente diverso.
    let fornitoreId = doc.fornitore_id;
    if (!fornitoreId && letto.fornitore?.partita_iva) {
      const { data: forn } = await mag
        .from('fornitore')
        .select('id')
        .eq('organizzazione_id', organizzazioneId)
        .eq('partita_iva', letto.fornitore.partita_iva.replace(/\D/g, ''))
        .maybeSingle();
      fornitoreId = forn?.id ?? null;
    }

    const testata: Record<string, unknown> = { stato: 'in_revisione' };
    if (fornitoreId) testata.fornitore_id = fornitoreId;

    // Il nome letto si salva SEMPRE, anche quando in anagrafica non c'e'
    // nessuno con quella partita IVA. Altrimenti l'elenco mostrerebbe
    // "Fornitore da indicare" su un documento di cui si sa benissimo il
    // mittente, e sembrerebbe che il sistema non abbia capito niente.
    if (letto.fornitore?.denominazione) {
      testata.fornitore_letto = letto.fornitore.denominazione;
    }
    if (letto.documento?.numero) testata.numero_documento = letto.documento.numero;
    if (letto.documento?.data) {
      testata.data_documento = letto.documento.data;
      testata.data_consegna = letto.documento.data;
    }
    if (letto.documento?.tipo) testata.tipo = letto.documento.tipo;

    // Solo le trascrizioni: i numeri li ricava il trigger
    // documento_converti_numeri. Nessun ripiego dal lordo all'imponibile: se
    // l'imponibile non si legge, `totale_dichiarato` resta vuoto e il confronto
    // con la somma delle righe semplicemente non si fa. Un confronto falso
    // sarebbe peggio di nessun confronto.
    if (letto.documento?.totale_imponibile_testo) {
      testata.totale_imponibile_testo = letto.documento.totale_imponibile_testo;
    }
    if (letto.documento?.totale_documento_testo) {
      testata.totale_documento_testo = letto.documento.totale_documento_testo;
    }

    await mag.from('documento_carico').update(testata).eq('id', documentoId);

    // ── Righe ───────────────────────────────────────────────────────────
    const righe = (letto.righe ?? [])
      .filter((r: Record<string, unknown>) => r.descrizione)
      .map((r: Record<string, unknown>, i: number) => ({
        documento_id: documentoId,
        numero_riga: i + 1,
        descrizione_originale: r.descrizione,
        codice_fornitore_originale: r.codice ?? null,
        um_dichiarata: r.unita_misura ?? null,
        // Solo le trascrizioni: i campi numerici li riempie il trigger
        // riga_converti_numeri, con magazzino.numero_it_da_testo().
        quantita_testo: r.quantita_testo ?? null,
        prezzo_testo: r.prezzo_testo ?? null,
        totale_testo: r.totale_testo ?? null,
        sconto_percentuale: r.sconto_percentuale ?? null,
        lotto_fornitore: r.lotto ?? null,
        data_scadenza: r.scadenza ?? null,
        stato_match: 'da_risolvere',
      }));

    if (righe.length === 0) {
      return risposta({
        documento_id: documentoId,
        righe: 0,
        avviso: 'Nessuna riga di merce riconosciuta. Controllare che la foto sia leggibile.',
      });
    }

    const { error: errRighe } = await mag.from('documento_carico_riga').insert(righe);
    if (errRighe) throw new Error(`Scrittura righe: ${errRighe.message}`);

    // ── Riconoscimento ──────────────────────────────────────────────────
    // Codice fornitore, alias, somiglianza. Il modello ha finito il suo
    // lavoro: da qui in avanti sono regole verificabili.
    const { data: riepilogo, error: errRis } = await mag.rpc('risolvi_documento', {
      p_documento_id: documentoId,
    });
    if (errRis) throw new Error(`Riconoscimento: ${errRis.message}`);

    return risposta({
      documento_id: documentoId,
      modello: MODELLO,
      durata_ms: durata,
      fornitore_letto: letto.fornitore?.denominazione ?? null,
      fornitore_agganciato: !!fornitoreId,
      numero_documento: letto.documento?.numero ?? null,
      imponibile_letto: letto.documento?.totale_imponibile_testo ?? null,
      totale_letto: letto.documento?.totale_documento_testo ?? null,
      ...riepilogo,
    });

  } catch (e) {
    const messaggio = e instanceof Error ? e.message : String(e);

    // Anche i fallimenti si registrano: senza, non si saprebbe mai quante
    // letture vanno male ne' perche'.
    if (documentoId && organizzazioneId) {
      await mag.from('estrazione_ai').insert({
        organizzazione_id: organizzazioneId,
        documento_id: documentoId,
        modello: MODELLO,
        versione_prompt: VERSIONE_PROMPT,
        stato: 'errore',
        errore: messaggio.slice(0, 2000),
        durata_ms: Date.now() - inizio,
      }).then(() => {}, () => {});
    }

    return risposta({ error: messaggio }, 500);
  }
});
