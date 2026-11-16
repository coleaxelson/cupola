import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// The slab the rows of her Requests page sit on: her other requests, and
/// her reports under them.
class RequestsSlab extends StatelessWidget {
  const RequestsSlab({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: BorderRadius.circular(AppRadius.slab),
        border: Border.all(color: room.hair),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
