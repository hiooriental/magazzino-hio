import 'package:flutter/material.dart';

/// Tiene il contenuto a una larghezza leggibile e lo centra.
///
/// Le schermate sono nate per il telefono — il magazzino si usa in piedi, in
/// mezzo alle casse. Su un monitor largo, stirate da bordo a bordo, moduli ed
/// elenchi diventano lenzuoli: l'occhio deve attraversare mezzo metro per
/// collegare un'etichetta al suo valore.
class ContenutoCentrato extends StatelessWidget {
  final Widget child;
  final double larghezzaMassima;

  const ContenutoCentrato({
    super.key,
    required this.child,
    this.larghezzaMassima = 1040,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: larghezzaMassima),
          child: child,
        ),
      );
}

/// Data in formato italiano senza dover inizializzare le localizzazioni.
String dataIt(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Importo in euro all'italiana: 1234.5 → "1.234,50 €".
String euro(num? v) {
  if (v == null) return '—';
  final parti = v.toStringAsFixed(2).split('.');
  final intero = parti[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  return '$intero,${parti[1]} €';
}

/// Numero all'italiana, senza decimali inutili: 1200 → "1.200", 8.5 → "8,5".
String numeroIt(num v) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  final parti = s.split('.');
  final intero = parti[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  return parti.length > 1 ? '$intero,${parti[1]}' : intero;
}

/// Quantità nell'unità in cui una persona la direbbe.
///
/// In magazzino tutto è in grammi e millilitri — una scelta che elimina
/// errori di conversione — ma "1200000 g" nessuno lo legge. Chi lavora dice
/// "1.200 kg", e sul documento c'era scritto proprio così.
String quantitaLeggibile(num? v, String umBase) {
  if (v == null) return '—';
  if (umBase == 'g' && v.abs() >= 1000) return '${numeroIt(v / 1000)} kg';
  if (umBase == 'ml' && v.abs() >= 1000) return '${numeroIt(v / 1000)} l';
  return '${numeroIt(v)} $umBase';
}
