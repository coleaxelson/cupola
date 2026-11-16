@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/widgets/hide_owned_switch.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'HideOwnedSwitch',
    scenes: [
      CatalogScene(
        'HideOwnedSwitch(value: false) · off: the words, and the switch at '
        'the end of the row',
        (_) => HideOwnedSwitch(value: false, onChanged: (_) {}),
        width: 390,
      ),
      CatalogScene(
        'HideOwnedSwitch(value: true) · on',
        (_) => HideOwnedSwitch(value: true, onChanged: (_) {}),
        width: 390,
      ),
      CatalogScene(
        'HideOwnedSwitch(value: null) · before the choice is known: the '
        'row has its words and its height, the switch\'s place is empty and '
        'nothing takes a tap',
        (_) => HideOwnedSwitch(value: null, onChanged: (_) {}),
        width: 390,
      ),
      CatalogScene(
        'On a tablet or a desktop window · the row is a phone\'s at most, '
        'at the head of the page, never a thousand points from its words',
        (_) => HideOwnedSwitch(value: true, onChanged: (_) {}),
        width: 1068,
      ),
      CatalogScene(
        'Text at 200% · the row grows with its words, the switch stays at the end',
        (_) => HideOwnedSwitch(value: false, onChanged: (_) {}),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
