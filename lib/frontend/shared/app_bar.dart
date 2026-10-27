import 'package:flutter/material.dart';

class SaamepAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SaamepAppBar({required this.title, this.actions, super.key});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: Text(title),
    actions: actions,
  );
}
