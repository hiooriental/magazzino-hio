# Magazzino HIO — schema database, Sezione 1

Schema `magazzino` dentro lo stesso progetto Supabase delle prenotazioni.
Le tabelle delle prenotazioni stanno in `public` e non vengono toccate.

## File, in ordine

| File | Cosa contiene |
|---|---|
| `migrations/20260903100000_magazzino_01_base.sql` | Schema, estensioni, funzioni comuni, organizzazione, utenti, depositi, fornitori, categorie, allergeni, ingredienti, articoli fornitore, alias |
| `migrations/20260903100100_magazzino_02_documenti_carico.sql` | Documenti di carico, righe, allegati (foto DDT), registro delle estrazioni AI |
| `migrations/20260903100200_magazzino_03_movimenti.sql` | Causali, lotti, libro mastro dei movimenti, viste di giacenza, inventari, storico prezzi |
| `migrations/20260903100300_magazzino_04_rls.sql` | Permessi e sicurezza a livello di riga |
| `dati_iniziali/01_hio.sql` | Dati di HIO: organizzazione, i cinque depositi, categorie. **Non e' una migrazione**, si esegue a mano una volta |

20 tabelle, 3 viste.

## Prima di eseguire

1. **Postgres 15 o superiore.** Servono `security_invoker` sulle viste e
   `UNIQUE NULLS NOT DISTINCT`. I progetti Supabase recenti ci sono già.
2. **Esporre lo schema**: Impostazioni → API → *Exposed schemas*, aggiungere
   `magazzino`. Senza, il client Flutter non lo vede.
3. Da Dart: `client.schema('magazzino').from('ingrediente')`.

## Dopo aver eseguito

Togliere il commento all'ultimo blocco di `dati_iniziali/01_hio.sql` per
assegnarsi il ruolo `titolare`. **Finché `utente_organizzazione` è vuota, ogni
query torna zero righe anche al titolare**: è la RLS che fa il suo lavoro, non
un errore.

## Decisioni prese, per non ridiscuterle fra sei mesi

- **Unità base solo `g`, `ml`, `pz`.** Mai kg o litri. Una sola scala elimina
  un'intera classe di errori di conversione.
- **Nessun campo "giacenza".** La giacenza è la somma dei movimenti. Costa
  qualche join in più e restituisce la capacità di spiegare sempre perché un
  numero è quello che è.
- **`movimento` è a sola aggiunta**, sia per trigger sia per assenza di policy.
  Un movimento sbagliato si corregge con uno storno che lo referenzia.
- **`estrazione_ai` è a sola aggiunta.** Quando un carico risulterà sbagliato,
  è l'unico modo per distinguere l'errore del modello da quello dell'operatore.
- **`quantita_reale` sulla riga**: il peso pesato in accettazione prevale su
  quello dichiarato sul DDT. La differenza accumulata per fornitore è uno dei
  dati più preziosi che il sistema produrrà.
- **Confermare un carico e chiudere un inventario sono riservati** a titolare e
  gestore. L'operatore compila, non chiude: sono gli atti che muovono il
  magazzino.
- **`ingrediente.vendibile_diretto`**: la bottiglia di gin è insieme prodotto
  venduto e componente dei cocktail. Una sola entità, due modi di scaricarla.
- **Multi-tenant dal primo giorno**, `organizzazione_id` ovunque.

## Cosa NON c'è ancora, di proposito

- **La funzione che conferma un carico**: da documento confermato a movimenti,
  lotti, storico prezzi e ricalcolo del costo medio. È logica di business e va
  scritta come funzione transazionale, non lasciata all'app. È il prossimo pezzo.
- **Storage**: bucket privato per le foto e sue policy.
- **Edge function di estrazione**: foto → modello → righe.
- **Tutta la Sezione 2**: distinte base, lavorazioni con rese, vendite iPratico.
  Nessuna di queste toccherà le tabelle qui dentro — `movimento` ha già
  `riferimento_tipo` / `riferimento_id` pronti per agganciarle.
