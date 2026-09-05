import 'package:flutter_test/flutter_test.dart';
import 'package:magazzino_hio/shared/widgets/contenuto_centrato.dart';

// Sostituisce il test di esempio di `flutter create`, che verificava una
// schermata non piu' esistente. Qui si prova cio' che ha davvero senso
// provare senza database: la formattazione dei numeri, che sulle schermate
// del magazzino l'operatore confronta a occhio con la carta che ha in mano.
void main() {
  group('euro', () {
    test('separa le migliaia col punto e i decimali con la virgola', () {
      expect(euro(5040), '5.040,00 €');
      expect(euro(6148.8), '6.148,80 €');
      expect(euro(1234567.5), '1.234.567,50 €');
    });

    test('sotto il migliaio non aggiunge separatori', () {
      expect(euro(7), '7,00 €');
      expect(euro(0.007), '0,01 €');
    });

    test('nessun valore si scrive con la lineetta, non con zero', () {
      // Zero e "non lo so" sono cose diverse: un totale mancante non deve
      // sembrare un documento da zero euro.
      expect(euro(null), '—');
      expect(euro(0), '0,00 €');
    });
  });

  group('dataIt', () {
    test('giorno e mese sempre a due cifre', () {
      expect(dataIt(DateTime(2026, 9, 4)), '04/09/2026');
      expect(dataIt(DateTime(2026, 12, 31)), '31/12/2026');
    });

    test('data mancante', () {
      expect(dataIt(null), '—');
    });
  });
}
