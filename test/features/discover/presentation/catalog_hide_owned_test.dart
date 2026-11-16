/// The value of "Hide what I have": the person's choice when there is one,
/// else the lens's Seerr (`hideAvailable`), else off.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  Future<ProviderContainer> container({
    bool? stored,
    bool configured = true,
    Future<SeerrServerFacts> Function()? facts,
    bool serverHides = false,
    List<String>? reads,
  }) async {
    SharedPreferences.setMockInitialValues({'catalog_hide_owned': ?stored});
    final prefs = await SharedPreferences.getInstance();
    final made = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices([if (configured) ServiceKey.seerr]),
        ),
        seerrServerFactsProvider.overrideWith((ref, id) {
          reads?.add(id);
          return facts?.call() ??
              Future.value(
                SeerrServerFacts.fromPublicSettings({
                  'hideAvailable': serverHides,
                }),
              );
        }),
      ],
    );
    addTearDown(made.dispose);
    return made;
  }

  test('unset, it follows the lens\'s Seerr', () async {
    final on = await container(serverHides: true);
    expect(await on.read(catalogHideOwnedProvider.future), isTrue);
    final off = await container();
    expect(await off.read(catalogHideOwnedProvider.future), isFalse);
  });

  test('the person\'s choice wins, and Seerr is not even asked', () async {
    final reads = <String>[];
    final off = await container(stored: false, serverHides: true, reads: reads);
    expect(await off.read(catalogHideOwnedProvider.future), isFalse);
    final on = await container(stored: true, reads: reads);
    expect(await on.read(catalogHideOwnedProvider.future), isTrue);
    expect(reads, isEmpty);
  });

  test('setting it keeps it, and it then wins over the server', () async {
    final made = await container(serverHides: true);
    expect(await made.read(catalogHideOwnedProvider.future), isTrue);

    made.read(catalogHideOwnedProvider.notifier).set(false);

    expect(made.read(catalogHideOwnedProvider).value, isFalse);
    expect(
      made.read(sharedPreferencesProvider).getBool('catalog_hide_owned'),
      isFalse,
    );
  });

  test('a Seerr that did not answer is off', () async {
    final made = await container(
      facts: () => Future.error(StateError('no answer')),
    );
    expect(await made.read(catalogHideOwnedProvider.future), isFalse);
  });

  test('with no Seerr set up it is off and nothing is asked', () async {
    final reads = <String>[];
    final made = await container(
      configured: false,
      serverHides: true,
      reads: reads,
    );
    expect(await made.read(catalogHideOwnedProvider.future), isFalse);
    expect(reads, isEmpty);
  });

  test('the lens\'s connection is the one asked', () async {
    final reads = <String>[];
    final made = await container(serverHides: true, reads: reads);
    await made.read(catalogHideOwnedProvider.future);
    expect(reads, hasLength(1));
    expect(
      reads.single,
      made.read(activeInstanceProvider(ServiceKey.seerr))?.id,
    );
  });
}
