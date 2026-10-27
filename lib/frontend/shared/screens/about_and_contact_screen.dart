import 'package:flutter/material.dart';

import 'package:i_am_astudent/backend/constants/api_constants.dart';
import 'package:i_am_astudent/backend/services/sync_service.dart';
import 'package:i_am_astudent/frontend/constants/app_colors.dart';

enum CommonPageSection { profile, about, support, settings }

class AboutAndContactScreen extends StatelessWidget {
  const AboutAndContactScreen({
    required this.section,
    required this.role,
    required this.email,
    super.key,
  });

  final CommonPageSection section;
  final String role;
  final String email;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (section) {
      CommonPageSection.profile => (
        'Profile / Account Info',
        _ProfileContent(role: role, email: email),
      ),
      CommonPageSection.about => ('About SAAMEP', const _AboutContent()),
      CommonPageSection.support => (
        'Help & Contact Us',
        _SupportContent(email: email),
      ),
      CommonPageSection.settings => (
        'Settings & Offline Sync',
        const _SettingsContent(),
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [body],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.role, required this.email});

  final String role;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.account_circle, size: 54, color: AppColors.ink),
            const SizedBox(height: 18),
            _DetailRow(label: 'Role', value: role),
            _DetailRow(label: 'Email', value: email),
          ],
        ),
      ),
    );
  }
}

class _AboutContent extends StatelessWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.school, size: 44, color: AppColors.ink),
            SizedBox(height: 16),
            Text(
              'Our mission',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'SAAMEP supports ministry exam preparation with accessible '
              'learning resources, practice, and progress tracking—even when '
              'a learner is offline.',
            ),
            SizedBox(height: 20),
            _DetailRow(label: 'App version', value: '1.0.0'),
            _DetailRow(label: 'Architecture', value: 'Offline-first Flutter'),
            _DetailRow(label: 'Local database', value: 'SQLite (sqflite)'),
          ],
        ),
      ),
    );
  }
}

class _SupportContent extends StatefulWidget {
  const _SupportContent({required this.email});

  final String email;

  @override
  State<_SupportContent> createState() => _SupportContentState();
}

class _SupportContentState extends State<_SupportContent> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _messageController;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await SyncService.instance.sendFeedback(
        email: widget.email,
        message: _messageController.text.trim(),
      );
      if (!mounted) return;
      _messageController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Your feedback was sent.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send feedback: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Contact support',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                ApiConstants.supportEmail.isEmpty
                    ? 'Administrator contact is not configured.'
                    : 'Administrator: ${ApiConstants.supportEmail}',
              ),
              const SizedBox(height: 20),
              TextFormField(
                initialValue: widget.email,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Your account email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _messageController,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Feedback or support request',
                  alignLabelWithHint: true,
                ),
                validator: (value) => (value?.trim().isNotEmpty ?? false)
                    ? null
                    : 'Enter a message before sending.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _sending ? null : _sendFeedback,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_sending ? 'Sending…' : 'Send feedback'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context) {
    final syncService = SyncService.instance;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: ValueListenableBuilder<SyncStatus>(
          valueListenable: syncService.status,
          builder: (context, status, _) {
            final isSyncing = status.state == SyncState.syncing;
            final label = switch (status.state) {
              SyncState.idle => 'Not started',
              SyncState.syncing => 'Syncing',
              SyncState.synced => 'Up to date',
              SyncState.offline => 'Offline',
              SyncState.error => 'Sync needs attention',
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offline data sync',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                _DetailRow(label: 'Status', value: label),
                if (status.message != null) ...[
                  const SizedBox(height: 8),
                  Text(status.message!),
                ],
                if (status.lastSyncedAt != null) ...[
                  const SizedBox(height: 8),
                  Text('Last synced: ${status.lastSyncedAt!.toLocal()}'),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: isSyncing
                      ? null
                      : () async {
                          try {
                            await syncService.syncPending();
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Sync failed: $error')),
                            );
                          }
                        },
                  icon: isSyncing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(isSyncing ? 'Syncing…' : 'Sync now'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Exam content and scores are saved locally first. They stay '
                  'on this device if sync is unavailable.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
