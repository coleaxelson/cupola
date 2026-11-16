/// An off switch has to be seen in both themes: its thumb and the track's edge
/// stand 3:1 off the room they sit in and off the track, and a switch that is
/// on keeps the framework's look.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final hi = math.max(_luminance(a), _luminance(b));
  final lo = math.min(_luminance(a), _luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (name, theme) in [
    ('dark', AppTheme.darkTheme()),
    ('light', AppTheme.lightTheme()),
  ]) {
    group('the $name theme’s off switch', () {
      final scheme = theme.colorScheme;
      final switches = theme.switchTheme;
      const off = <WidgetState>{};

      test('thumb and edge are 3:1 off the ground and off the track', () {
        final thumb = switches.thumbColor!.resolve(off)!;
        final edge = switches.trackOutlineColor!.resolve(off)!;
        expect(_contrast(edge, scheme.surface), greaterThanOrEqualTo(3));
        expect(
          _contrast(thumb, scheme.surfaceContainerHighest),
          greaterThanOrEqualTo(3),
        );
      });

      test('is monochrome: the secondary ink, never a tone', () {
        expect(switches.thumbColor!.resolve(off), scheme.onSurfaceVariant);
        expect(
          switches.trackOutlineColor!.resolve(off),
          scheme.onSurfaceVariant,
        );
      });

      test('an on or a disabled switch keeps the framework’s look', () {
        for (final state in [WidgetState.selected, WidgetState.disabled]) {
          expect(switches.thumbColor!.resolve({state}), isNull);
          expect(switches.trackOutlineColor!.resolve({state}), isNull);
        }
      });
    });
  }
}
