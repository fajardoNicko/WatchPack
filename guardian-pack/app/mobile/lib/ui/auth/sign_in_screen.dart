import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../auth/auth.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

enum _Mode { signIn, create }

/// Parent sign-in. One screen, two modes, no social buttons.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    final auth = ref.read(authActionsProvider);
    try {
      if (_mode == _Mode.signIn) {
        await auth.signIn(_email.text, _password.text);
      } else {
        await auth.signUp(_email.text, _password.text, _name.text);
      }
      // authStateProvider flips and the app shell takes over.
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Type your email above first, then tap "Forgot password".');
      return;
    }
    try {
      await ref.read(authActionsProvider).sendReset(email);
      if (mounted) showNote(context, 'Reset link sent to $email.');
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final create = _mode == _Mode.create;
    return Scaffold(
      backgroundColor: WpColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WpSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(padding: EdgeInsets.only(bottom: WpSpace.xxl), child: Center(child: Wordmark(size: 34))),
                  WpCard(
                    padding: const EdgeInsets.all(WpSpace.xl),
                    child: Form(
                      key: _form,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(create ? 'Create a parent account' : 'Welcome back', style: t.titleLarge),
                            const SizedBox(height: WpSpace.xs),
                            Text(create ? 'Your account is what links you to your child\'s WatchPack.' : 'Sign in to see where your child is.', style: t.bodySmall),
                            const SizedBox(height: WpSpace.xl),
                            if (create) ...[
                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                autofillHints: const [AutofillHints.name],
                                decoration: _dec('Your name', Symbols.person_rounded),
                                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                              ),
                              const SizedBox(height: WpSpace.m),
                            ],
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: _dec('Email', Symbols.mail_rounded),
                              validator: (v) => !(v ?? '').contains('@') ? 'Enter a valid email' : null,
                            ),
                            const SizedBox(height: WpSpace.m),
                            TextFormField(
                              controller: _password,
                              obscureText: !_showPassword,
                              autofillHints: [create ? AutofillHints.newPassword : AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              decoration: _dec('Password', Symbols.lock_rounded).copyWith(
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _showPassword = !_showPassword),
                                  icon: Icon(_showPassword ? Symbols.visibility_off_rounded : Symbols.visibility_rounded),
                                ),
                              ),
                              validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: WpSpace.m),
                              Container(
                                padding: const EdgeInsets.all(WpSpace.m),
                                decoration: BoxDecoration(color: WpColors.redSoft, borderRadius: BorderRadius.circular(WpRadius.button)),
                                child: Row(children: [
                                  const Icon(Symbols.error_rounded, color: WpColors.red, size: 20),
                                  const SizedBox(width: WpSpace.s),
                                  Expanded(child: Text(_error!, style: t.bodySmall!.copyWith(color: WpColors.red))),
                                ]),
                              ),
                            ],
                            const SizedBox(height: WpSpace.xl),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(_busy ? 'Please wait…' : (create ? 'Create account' : 'Sign in')),
                            ),
                            if (!create) TextButton(onPressed: _busy ? null : _reset, child: const Text('Forgot password?')),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: WpSpace.l),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() { _mode = create ? _Mode.signIn : _Mode.create; _error = null; }),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(create ? 'Already have an account? Sign in' : 'New here? Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(WpRadius.button)),
      );
}
