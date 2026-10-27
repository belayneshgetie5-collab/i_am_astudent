import 'package:flutter/material.dart';

class RequiredPasswordResetDialog extends StatefulWidget {
  const RequiredPasswordResetDialog({super.key});

  @override
  State<RequiredPasswordResetDialog> createState() =>
      _RequiredPasswordResetDialogState();
}

class _RequiredPasswordResetDialogState
    extends State<RequiredPasswordResetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Set a new password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your administrator issued a temporary password. '
              'Choose a new password to continue.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (value) => (value?.length ?? 0) >= 8
                  ? null
                  : 'Use at least 8 characters.',
            ),
            TextFormField(
              controller: _confirmation,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
              validator: (value) =>
                  value == _password.text ? null : 'Passwords do not match.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, _password.text);
            }
          },
          child: const Text('Save password'),
        ),
      ],
    ),
  );
}
