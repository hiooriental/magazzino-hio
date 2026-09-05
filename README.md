# Magazzino HIO

Magazzino, acquisti e food cost per **HIO Oriental**.

Si fotografa un DDT o una fattura del fornitore, l'AI legge le righe, chi lavora
conferma, e la merce entra in magazzino con lotti, costi e storico prezzi.
Il sistema impara: ogni abbinamento confermato una volta diventa automatico
per sempre.

**In produzione:** https://magazzino.hiooriental.com

## Stack

Flutter Web + Supabase (Postgres, Auth, Storage, Edge Functions), Riverpod,
GoRouter. Pubblicazione automatica su GitHub Pages a ogni push su `main`.

Condivide il progetto Supabase con
[restaurant-booking](https://github.com/hiooriental/restaurant-booking): stesso
`auth.users`, quindi un solo login per il personale. Le tabelle del magazzino
stanno nello schema **`magazzino`**, quelle delle prenotazioni in `public`.

## Avvio locale

Flutter non è nel PATH, sta in `C:\src\flutter` ed è pinnato a **3.27.4**
(il codice usa `Color.withValues()`, che esiste solo da 3.27):

```powershell
$env:PATH = "C:\src\flutter\bin;" + $env:PATH
```

Il `.env` non è in git. Va creato con le stesse chiavi di restaurant-booking:

```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
```

```powershell
flutter pub get
flutter run -d chrome
```

## Database

Le migrazioni stanno in `supabase/migrations/`, numerate e da eseguire in
ordine. **Lo schema si cambia solo da file versionati, mai cliccando nella
dashboard.**

Non si usa `supabase db push`: la cronologia delle migrazioni vive nel
database ed è condivisa con restaurant-booking, quindi la CLI si troverebbe
davanti a una cronologia che non le torna. Si esegue dal SQL Editor.

| Cartella | Cosa contiene |
|---|---|
| `supabase/migrations/` | Lo schema, in ordine |
| `supabase/dati_iniziali/` | Dati di HIO. Non è schema, si esegue a mano una volta |
| `supabase/functions/estrai-ddt/` | Lettura AI delle foto |
| `supabase/verifica.sql` | 13 controlli sullo stato dell'installazione |
| `supabase/prova_*.sql` | Collaudi in transazione annullata: non lasciano traccia |

Dopo ogni modifica allo schema, `verifica.sql` deve restare tutto verde.

## Decisioni da non ridiscutere

- **Unità base solo `g`, `ml`, `pz`.** Mai kg o litri: una sola scala elimina
  un'intera classe di errori di conversione.
- **Nessun campo "giacenza".** È la somma dei movimenti. Costa qualche join e
  restituisce la capacità di spiegare sempre perché un numero è quello che è.
- **`movimento` è a sola aggiunta**, per trigger e per assenza di policy. Un
  movimento sbagliato si corregge con uno storno che lo referenzia.
- **Il modello di visione non interpreta i numeri.** Trascrive la stringa
  stampata (`"720.000,00"`) nei campi `*_testo`, e un trigger la converte con
  `magazzino.numero_it_da_testo()`. Lasciandogli fare la conversione, su una
  fattura vera ha cambiato quantità *e* prezzo insieme perché il totale
  tornasse: un errore coerente supera qualunque controllo aritmetico.
- **In `totale_dichiarato` va solo l'imponibile**, mai il lordo come ripiego.
  Un allarme che suona a ogni documento è un allarme spento.
- **Multi-tenant dal primo giorno**, `organizzazione_id` ovunque, nessun
  identificativo scritto nel codice.

## Pubblicazione

Automatica su push a `main` (`.github/workflows/deploy.yml`).

Il dominio è scritto come `cname:` nel workflow e **non solo** nelle
impostazioni di Pages: ogni pubblicazione riscrive `gh-pages` e cancellerebbe
l'impostazione fatta a mano.

Servono due segreti nel repo: `SUPABASE_URL` e `SUPABASE_ANON_KEY`.
