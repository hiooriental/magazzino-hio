# CLAUDE.md

Indicazioni per Claude Code quando lavora in questo repository.

## Comandi

Flutter non è nel PATH. Prefissare sempre:

```powershell
$env:PATH = "C:\src\flutter\bin;" + $env:PATH
```

```powershell
flutter pub get
flutter run -d chrome
flutter analyze          # esce comunque con codice 1: filtrare per "error -"
flutter test
dart format lib test
flutter build web --release --base-href "/"
```

## Architettura

**Flutter Web + Supabase + Riverpod + GoRouter.** Deploy automatico su
GitHub Pages a ogni push su `main` → `magazzino.hiooriental.com`.

### Supabase

Stesso progetto di `restaurant-booking` (ref `jxdnldyabhzmfnterzil`), ma le
tabelle stanno nello schema **`magazzino`**, non in `public`.

- Ogni query passa da `Db.mag` (`lib/core/db.dart`), che è
  `client.schema('magazzino')`. Usare il client globale direttamente non
  funziona: PostgREST cercherebbe in `public`.
- Lo schema dev'essere negli *Exposed schemas* del progetto.
- **Nessun identificativo di organizzazione scritto nel codice.**
  `lib/core/sessione.dart` legge organizzazione e ruolo da
  `utente_organizzazione` all'avvio. È ciò che tiene aperta la strada della
  rivendita senza riscrivere le query.

### Un solo modo di accedere ai dati

Tutte le chiamate stanno in `lib/data/magazzino_repository.dart`. Non scrivere
query dentro le schermate: con quantità e costi in ballo, una query sparsa è
il modo più rapido per scoprire fra tre mesi che un numero è sbagliato senza
sapere dove.

### La logica sta nel database, non nell'app

Abbinare una riga tocca articolo, alias e righe. Confermare un carico tocca
movimenti, lotti, prezzi e costo medio. Sono funzioni PL/pgSQL
(`conferma_carico`, `abbina_riga`, `risolvi_documento`, `storna_carico`), non
sequenze di chiamate dall'app: se la connessione cade a metà deve non essere
successo niente, e questo lo garantisce solo una transazione lato server.

I messaggi delle `raise exception` sono scritti per essere letti da una
persona: si mostrano all'operatore così come sono.

### Le regole non si duplicano in Dart

Se serve sapere se un'unità è convertibile, si chiama `converti_um` via RPC —
la stessa funzione che usa il riconoscimento. Due copie della stessa regola
prima o poi divergono.

### Schermate

| Schermata | File |
|---|---|
| Accesso | `features/auth/accesso_screen.dart` |
| Elenco documenti | `features/documenti/documenti_screen.dart` |
| Revisione di un documento | `features/documenti/documento_screen.dart` |
| Pannello di abbinamento | `features/documenti/abbina_sheet.dart` |
| Foto di un nuovo documento | `features/documenti/nuovo_documento_screen.dart` |

L'elenco legge dalla vista `documento_riepilogo`, non dalla tabella: porta già
fornitore, conteggi e anteprima del contenuto.

Nella revisione le righe sono ordinate **al contrario del solito**: prima
quelle da risolvere, in fondo quelle già a posto. Il valore del sistema si
misura in quante righe non devi guardare.

### Tema

`lib/shared/theme/app_theme.dart`, copiato da restaurant-booking. Rosso HIO
`#B9172A`, oro `#CAB16F`. **L'oro non si usa mai come testo su fondo chiaro**
(contrasto 2,2:1): per i testi c'è `goldDark`.

## Database: cosa non cambiare

- Unità base solo `g`, `ml`, `pz`.
- Nessun campo "giacenza": è la somma dei movimenti.
- `movimento` ed `estrazione_ai` sono a sola aggiunta.
- Il modello di visione **trascrive** i numeri nei campi `*_testo`, non li
  converte. Ci pensa `numero_it_da_testo()` con regole fisse. Non tornare
  indietro: lasciandogli fare la conversione, su una fattura vera ha cambiato
  quantità e prezzo insieme perché il totale tornasse.
- `totale_dichiarato` è l'imponibile. Mai il lordo come ripiego.
- Soglie del riconoscimento: ≥0,90 automatico, ≥0,55 proposta. Non abbassarle.
  La somiglianza testuale non arriva mai all'automatico da sola, ed è voluto:
  ci arrivano solo codice, EAN, descrizione identica e alias.
- Aggiungere un metodo di riconoscimento richiede di aggiornare **anche** il
  CHECK su `documento_carico_riga.metodo_match`.

## Migrazioni

In `supabase/migrations/`, numerate, da eseguire **in ordine dal SQL Editor**.
Non usare `supabase db push`: la cronologia è condivisa con restaurant-booking.

Ogni modifica allo schema passa da un file versionato. Mai dalla dashboard.

Dopo ogni migrazione, `supabase/verifica.sql` deve restare tutto verde. I file
`prova_*.sql` girano dentro `begin ... rollback` e non lasciano traccia.
