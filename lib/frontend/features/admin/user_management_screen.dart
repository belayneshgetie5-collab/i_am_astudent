import 'package:flutter/material.dart';

import 'package:i_am_astudent/database/db_helper.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late Future<List<Map<String, Object?>>> _users;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => _users = DbHelper.instance.getUsers();

  Future<void> _editUser([Map<String, Object?>? existing]) async {
    final draft = await showDialog<_UserDraft>(
      context: context,
      builder: (context) => _UserFormDialog(user: existing),
    );
    if (draft == null || !mounted) return;
    try {
      if (existing == null) {
        await DbHelper.instance.createUser(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          email: draft.email,
          displayName: draft.name,
          role: draft.role,
          parentEmail: draft.parentEmail,
        );
      } else {
        await DbHelper.instance.updateUser(existing['id']! as String, {
          'display_name': draft.name,
          'role': draft.role,
          'parent_email': draft.parentEmail,
        });
      }
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save user: $error')));
    }
  }

  Future<void> _deleteUser(Map<String, Object?> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove user?'),
        content: Text(
          'Remove ${user['display_name']} from this device and queue the '
          'change for cloud sync?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DbHelper.instance.deleteUser(user['id']! as String);
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not remove user: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editUser(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add user'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load users: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('No cached users are available.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = snapshot.data![index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text((user['display_name']! as String)[0]),
                  ),
                  title: Text(user['display_name']! as String),
                  subtitle: Text(
                    '${user['email']} · ${(user['role']! as String).toUpperCase()}',
                  ),
                  onTap: () => _editUser(user),
                  trailing: IconButton(
                    tooltip: 'Remove user',
                    onPressed: () => _deleteUser(user),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserDraft {
  const _UserDraft({
    required this.email,
    required this.name,
    required this.role,
    this.parentEmail,
  });

  final String email;
  final String name;
  final String role;
  final String? parentEmail;
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user});

  final Map<String, Object?>? user;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _name;
  late final TextEditingController _parentEmail;
  late String _role;

  static const _roles = ['student', 'teacher', 'parent', 'admin'];

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(
      text: widget.user?['email'] as String? ?? '',
    );
    _name = TextEditingController(
      text: widget.user?['display_name'] as String? ?? '',
    );
    _parentEmail = TextEditingController(
      text: widget.user?['parent_email'] as String? ?? '',
    );
    final role = widget.user?['role'] as String?;
    _role = role != null && _roles.contains(role) ? role : _roles.first;
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _parentEmail.dispose();
    super.dispose();
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
        ? null
        : 'Enter a valid email address.';
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.user != null;
    return AlertDialog(
      title: Text(editing ? 'Edit user' : 'Add user'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _email,
                readOnly: editing,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: _emailValidator,
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (value) => value?.trim().isNotEmpty ?? false
                    ? null
                    : 'Enter a display name.',
              ),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role[0].toUpperCase() + role.substring(1)),
                      ),
                    )
                    .toList(),
                onChanged: (role) {
                  if (role != null) setState(() => _role = role);
                },
              ),
              if (_role == 'student')
                TextFormField(
                  controller: _parentEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Linked parent email (optional)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return _emailValidator(value);
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _UserDraft(
                email: _email.text.trim(),
                name: _name.text.trim(),
                role: _role,
                parentEmail: _parentEmail.text.trim().isEmpty
                    ? null
                    : _parentEmail.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
