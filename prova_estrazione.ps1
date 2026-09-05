# ============================================================================
#  Collaudo di estrai-ddt con una foto vera
# ============================================================================
#
#  Fa il giro completo, quello che poi fara' la app:
#    1. entra come utente vero (non con la chiave di servizio: cosi' si
#       collauda anche la sicurezza, non solo la lettura)
#    2. crea un documento in bozza
#    3. carica la foto su Storage nel percorso giusto
#    4. registra l'allegato
#    5. chiama la edge function
#    6. rilegge le righe e le stampa
#
#  Il documento resta in bozza: nessun movimento di magazzino viene generato.
#  Alla fine ti dice come cancellarlo.
#
#  Uso, dal tuo terminale (non dal pulsante Esegui: chiede la password):
#
#      .\prova_estrazione.ps1 -Foto "C:\percorso\della\foto.jpg"
#
# ============================================================================

param(
  [Parameter(Mandatory = $true)]
  [string] $Foto,

  [string] $Email = 'admin@hiooriental.com',

  # Le chiavi si leggono dal .env delle prenotazioni: stesso progetto Supabase,
  # quindi stesse chiavi. Cosi' non c'e' niente da copiare a mano.
  [string] $FileEnv = 'C:\Users\peppe\Desktop\restaurant-booking\.env',

  [string] $Organizzazione = '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d'
)

$ErrorActionPreference = 'Stop'

function Passo($testo) { Write-Host "`n>> $testo" -ForegroundColor Cyan }
function Ok($testo)    { Write-Host "   $testo" -ForegroundColor Green }

if (-not (Test-Path $Foto))    { throw "Foto non trovata: $Foto" }
if (-not (Test-Path $FileEnv)) { throw "File .env non trovato: $FileEnv" }

# ── Chiavi ──────────────────────────────────────────────────────────────────
$env_righe = Get-Content $FileEnv
$SupaUrl = ($env_righe | Where-Object { $_ -match '^\s*SUPABASE_URL\s*=' }) -replace '^\s*SUPABASE_URL\s*=\s*', '' -replace '"', ''
$AnonKey = ($env_righe | Where-Object { $_ -match '^\s*SUPABASE_ANON_KEY\s*=' }) -replace '^\s*SUPABASE_ANON_KEY\s*=\s*', '' -replace '"', ''
$SupaUrl = $SupaUrl.Trim().TrimEnd('/')
$AnonKey = $AnonKey.Trim()

if (-not $SupaUrl -or -not $AnonKey) { throw "SUPABASE_URL o SUPABASE_ANON_KEY non trovate in $FileEnv" }
Ok "Progetto: $SupaUrl"

# ── 1. Accesso ──────────────────────────────────────────────────────────────
Passo "Accesso come $Email"
$pwdSicura = Read-Host "   Password di $Email" -AsSecureString
$pwdChiara = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
               [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwdSicura))

$accesso = Invoke-RestMethod -Method Post `
  -Uri "$SupaUrl/auth/v1/token?grant_type=password" `
  -Headers @{ apikey = $AnonKey } `
  -ContentType 'application/json' `
  -Body (@{ email = $Email; password = $pwdChiara } | ConvertTo-Json)

$token = $accesso.access_token
if (-not $token) { throw "Accesso fallito." }
Ok "Entrato."

$intestazioni = @{
  apikey        = $AnonKey
  Authorization = "Bearer $token"
}

# Le tabelle stanno nello schema `magazzino`, non in `public`: PostgREST lo
# vuole sapere con queste due intestazioni.
$intRest = $intestazioni + @{
  'Accept-Profile'  = 'magazzino'
  'Content-Profile' = 'magazzino'
  'Prefer'          = 'return=representation'
}

# ── 2. Documento in bozza ───────────────────────────────────────────────────
Passo "Creo il documento in bozza"
$oggi = (Get-Date).ToString('yyyy-MM-dd')

$documento = Invoke-RestMethod -Method Post `
  -Uri "$SupaUrl/rest/v1/documento_carico" `
  -Headers $intRest -ContentType 'application/json' `
  -Body (@{
      organizzazione_id = $Organizzazione
      tipo              = 'ddt'
      origine           = 'foto'
      data_documento    = $oggi
      data_consegna     = $oggi
      stato             = 'bozza'
      note              = 'Collaudo estrazione'
    } | ConvertTo-Json)

$docId = $documento[0].id
Ok "Documento $docId"

# ── 3. Foto su Storage ──────────────────────────────────────────────────────
Passo "Carico la foto"
$estensione = ([IO.Path]::GetExtension($Foto)).TrimStart('.').ToLower()
$tipoMime = switch ($estensione) {
  'jpg'  { 'image/jpeg' }
  'jpeg' { 'image/jpeg' }
  'png'  { 'image/png' }
  'heic' { 'image/heic' }
  'webp' { 'image/webp' }
  default { throw "Formato non gestito: .$estensione" }
}

# Stessa convenzione della funzione SQL percorso_allegato().
$percorso = "$Organizzazione/$docId/01.$estensione"
$dimensione = (Get-Item $Foto).Length

Invoke-RestMethod -Method Post `
  -Uri "$SupaUrl/storage/v1/object/documenti-magazzino/$percorso" `
  -Headers $intestazioni -ContentType $tipoMime -InFile $Foto | Out-Null

Ok "Caricata: $percorso ($([math]::Round($dimensione/1MB, 2)) MB)"

Passo "Registro l'allegato"
Invoke-RestMethod -Method Post `
  -Uri "$SupaUrl/rest/v1/allegato" `
  -Headers $intRest -ContentType 'application/json' `
  -Body (@{
      organizzazione_id = $Organizzazione
      documento_id      = $docId
      percorso_storage  = $percorso
      nome_file         = [IO.Path]::GetFileName($Foto)
      tipo_mime         = $tipoMime
      dimensione_byte   = $dimensione
      pagina            = 1
    } | ConvertTo-Json) | Out-Null
Ok "Registrato."

# ── 4. La lettura ───────────────────────────────────────────────────────────
Passo "Chiamo estrai-ddt (puo' richiedere un minuto)"
$inizio = Get-Date

try {
  $esito = Invoke-RestMethod -Method Post `
    -Uri "$SupaUrl/functions/v1/estrai-ddt" `
    -Headers $intestazioni -ContentType 'application/json' `
    -Body (@{ documento_id = $docId } | ConvertTo-Json)
} catch {
  $corpo = $_.ErrorDetails.Message
  Write-Host "`nLa funzione ha risposto con un errore:" -ForegroundColor Red
  Write-Host $corpo
  Write-Host "`nDocumento di prova: $docId" -ForegroundColor Yellow
  exit 1
}

Ok "Risposta in $([math]::Round(((Get-Date) - $inizio).TotalSeconds, 1)) s"
Write-Host ""
$esito | ConvertTo-Json -Depth 5

# ── 5. Le righe ─────────────────────────────────────────────────────────────
Passo "Righe estratte"
$campi = 'numero_riga,descrizione_originale,codice_fornitore_originale,' +
         'quantita_testo,prezzo_testo,totale_testo,' +
         'quantita_dichiarata,um_dichiarata,prezzo_unitario,totale_riga,' +
         'quantita_base,stato_match,confidenza,metodo_match,note'

$righe = Invoke-RestMethod -Method Get `
  -Uri "$SupaUrl/rest/v1/documento_carico_riga?documento_id=eq.$docId&select=$campi&order=numero_riga" `
  -Headers $intRest

# Trascritto e convertito affiancati: e' l'unico modo di vedere a colpo
# d'occhio se la conversione dei separatori ha fatto quello che doveva.
$righe | Format-Table `
  @{L='#';   E={$_.numero_riga}},
  @{L='Descrizione'; E={$_.descrizione_originale}},
  @{L='Cod'; E={$_.codice_fornitore_originale}},
  @{L='UM';  E={$_.um_dichiarata}},
  @{L='Qta letta'; E={$_.quantita_testo}},
  @{L='Qta';       E={$_.quantita_dichiarata}},
  @{L='Prezzo letto'; E={$_.prezzo_testo}},
  @{L='Prezzo';       E={$_.prezzo_unitario}},
  @{L='Tot letto'; E={$_.totale_testo}},
  @{L='Tot';       E={$_.totale_riga}},
  @{L='Stato'; E={$_.stato_match}} -AutoSize -Wrap

$conNote = $righe | Where-Object { $_.note }
if ($conNote) {
  Write-Host ""
  Write-Host "Righe segnalate:" -ForegroundColor Yellow
  foreach ($r in $conNote) { Write-Host "  riga $($r.numero_riga): $($r.note)" }
}

# ── 6. Confronto col documento vero ─────────────────────────────────────────
Write-Host ""
Write-Host "Ora confronta con la foto:" -ForegroundColor Yellow
Write-Host "  - il numero di righe corrisponde?"
Write-Host "  - le descrizioni sono copiate esatte, senza espansioni inventate?"
Write-Host "  - quantita' e prezzi sono giusti, virgole comprese?"
Write-Host "  - il totale dichiarato letto e' quello stampato sul documento?"
Write-Host ""
Write-Host "Documento di prova: $docId" -ForegroundColor Yellow
Write-Host "Per cancellarlo, dal SQL Editor:" -ForegroundColor Yellow
Write-Host "  delete from magazzino.documento_carico where id = '$docId';"
Write-Host "(le righe e gli allegati se ne vanno con lui; la foto resta su Storage)"
