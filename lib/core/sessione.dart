import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';

/// A quale organizzazione appartiene chi ha fatto l'accesso, e con che ruolo.
///
/// In restaurant-booking l'identificativo del ristorante e' scritto a mano nel
/// codice. Qui no, e non e' un vezzo: e' cio' che permette di vendere lo
/// stesso software a un secondo locale senza riscrivere le query. Il costo e'
/// una lettura in piu' all'avvio.
class Sessione {
  final String organizzazioneId;
  final String organizzazione;
  final String ruolo;

  const Sessione({
    required this.organizzazioneId,
    required this.organizzazione,
    required this.ruolo,
  });

  /// Confermare un carico e chiudere un inventario sono gli atti che muovono
  /// il magazzino. L'operatore compila e fotografa, ma non chiude.
  ///
  /// Qui serve solo a non mostrare pulsanti che poi darebbero errore: la
  /// regola vera sta nelle policy del database, dove non si aggira.
  bool get puoConfermare => ruolo == 'titolare' || ruolo == 'gestore';
  bool get eTitolare => ruolo == 'titolare';
}

/// Nessuna appartenenza trovata: succede a un utente che esiste in
/// `auth.users` ma che nessuno ha ancora abilitato al magazzino. Va detto
/// chiaramente, perche' altrimenti l'app sembra vuota e rotta invece che
/// semplicemente non abilitata.
class NonAbilitato implements Exception {
  const NonAbilitato();
  @override
  String toString() => 'Utente non abilitato al magazzino.';
}

final sessioneProvider = FutureProvider<Sessione>((ref) async {
  final utente = Db.utente;
  if (utente == null) throw const NonAbilitato();

  final riga = await Db.mag
      .from('utente_organizzazione')
      .select('ruolo, organizzazione_id, organizzazione(nome)')
      .eq('utente_id', utente.id)
      .eq('attivo', true)
      .maybeSingle();

  if (riga == null) throw const NonAbilitato();

  return Sessione(
    organizzazioneId: riga['organizzazione_id'] as String,
    organizzazione:
        (riga['organizzazione'] as Map?)?['nome'] as String? ?? 'Magazzino',
    ruolo: riga['ruolo'] as String,
  );
});
