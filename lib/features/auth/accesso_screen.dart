import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/db.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/contenuto_centrato.dart';
import '../../shared/widgets/logo_hio.dart';

/// Accesso con la stessa utenza del gestionale prenotazioni: un solo database,
/// quindi un solo `auth.users` e una sola password da ricordare.
class AccessoScreen extends StatefulWidget {
  const AccessoScreen({super.key});

  @override
  State<AccessoScreen> createState() => _AccessoScreenState();
}

class _AccessoScreenState extends State<AccessoScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _modulo = GlobalKey<FormState>();

  bool _inCorso = false;
  bool _nascosta = true;
  String? _errore;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entra() async {
    if (!_modulo.currentState!.validate()) return;
    setState(() {
      _inCorso = true;
      _errore = null;
    });

    try {
      await Db.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      // Il redirect del router porta ai documenti da solo, appena
      // onAuthStateChange notifica il cambio.
    } on AuthException catch (e) {
      // Messaggio nostro: "Invalid login credentials" non dice niente a chi
      // sta lavorando, e in inglese ancora meno.
      setState(() => _errore = e.message.contains('Invalid login')
          ? 'Indirizzo o password non corretti.'
          : e.message);
    } catch (e) {
      setState(() => _errore = 'Non riesco a collegarmi: $e');
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ContenutoCentrato(
        larghezzaMassima: 420,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _modulo,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                const Center(child: LogoHio(larghezza: 220)),
                const SizedBox(height: 8),
                Text(
                  'Magazzino',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.goldDark,
                      ),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration:
                      const InputDecoration(labelText: 'Indirizzo email'),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Serve un indirizzo email'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: _nascosta,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _entra(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_nascosta
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      color: AppColors.textSecondary,
                      onPressed: () => setState(() => _nascosta = !_nascosta),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Serve la password' : null,
                ),
                if (_errore != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _errore!,
                      style: const TextStyle(color: AppColors.accentDark),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _inCorso ? null : _entra,
                  child: _inCorso
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Entra'),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
