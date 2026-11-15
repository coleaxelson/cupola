import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/lidarr_add_options.dart';
import 'package:cupola/features/music/domain/lidarr_monitor.dart';
import 'package:cupola/features/music/domain/models/lidarr_metadata_profile.dart';

void main() {
  group('LidarrMonitor', () {
    test('sends Lidarr the seven words of its MonitorTypes', () {
      expect(LidarrMonitor.values.map((m) => m.wireValue), [
        'all',
        'future',
        'missing',
        'existing',
        'first',
        'latest',
        'none',
      ]);
    });

    test('says what each choice means, in words of its own', () {
      expect(LidarrMonitor.all.label, 'All albums');
      expect(LidarrMonitor.all.meaning, 'Every album, out and to come');
      expect(LidarrMonitor.none.label, 'None');
      expect(
        LidarrMonitor.none.meaning,
        'Lists the artist and looks for nothing',
      );
      final meanings = LidarrMonitor.values.map((m) => m.meaning).toSet();
      expect(meanings, hasLength(LidarrMonitor.values.length));
    });

    test('reads a default from the root folder, or none for a stranger', () {
      expect(LidarrMonitor.fromWire('latest'), LidarrMonitor.latest);
      expect(LidarrMonitor.fromWire('unknown'), isNull);
      expect(LidarrMonitor.fromWire(null), isNull);
    });
  });

  group('LidarrRootFolder', () {
    test('reads the defaults Lidarr sends', () {
      final folder = LidarrRootFolder.tryParse({
        'path': '/music',
        'freeSpace': 2100000000000,
        'defaultQualityProfileId': 2,
        'defaultMetadataProfileId': 1,
        'defaultMonitorOption': 'future',
        'defaultNewItemMonitorOption': 'none',
      })!;

      expect(folder.path, '/music');
      expect(folder.freeSpace, 2100000000000);
      expect(folder.defaultQualityProfileId, 2);
      expect(folder.defaultMetadataProfileId, 1);
      expect(folder.defaultMonitor, LidarrMonitor.future);
      expect(folder.defaultNewItemMonitor, 'none');
    });

    test('a profile id of zero is no default', () {
      final folder = LidarrRootFolder.tryParse({
        'path': '/music',
        'defaultQualityProfileId': 0,
        'defaultMetadataProfileId': 0,
      })!;

      expect(folder.defaultQualityProfileId, isNull);
      expect(folder.defaultMetadataProfileId, isNull);
      expect(folder.defaultMonitor, isNull);
      expect(folder.defaultNewItemMonitor, isNull);
    });

    test('an entry with no path is not a place to file under', () {
      expect(LidarrRootFolder.tryParse({'id': 1}), isNull);
      expect(LidarrRootFolder.tryParse({'path': ''}), isNull);
    });
  });

  group('LidarrAddOptions', () {
    test('names what a Lidarr without it lacks', () {
      const folder = LidarrRootFolder(path: '/music');
      const metadata = LidarrMetadataProfile(id: 1, name: 'Standard');
      expect(
        const LidarrAddOptions(
          folders: [],
          qualityProfiles: [(id: 1, name: 'Lossless')],
          metadataProfiles: [metadata],
        ).missing,
        'root folder',
      );
      expect(
        const LidarrAddOptions(
          folders: [folder],
          qualityProfiles: [],
          metadataProfiles: [metadata],
        ).missing,
        'quality profile',
      );
      expect(
        const LidarrAddOptions(
          folders: [folder],
          qualityProfiles: [(id: 1, name: 'Lossless')],
          metadataProfiles: [],
        ).missing,
        'metadata profile',
      );
      expect(
        const LidarrAddOptions(
          folders: [folder],
          qualityProfiles: [(id: 1, name: 'Lossless')],
          metadataProfiles: [metadata],
        ).missing,
        isNull,
      );
    });
  });

  group('LidarrMetadataProfile.typesLine', () {
    String? line(List<String> types) => LidarrMetadataProfile(
      id: 1,
      name: 'p',
      allowedPrimaryTypes: types,
    ).typesLine;

    test('lists the allowed types in plural, the last after an and', () {
      expect(line(['Album']), 'Albums');
      expect(line(['Album', 'EP']), 'Albums and EPs');
      expect(line(['Album', 'EP', 'Single']), 'Albums, EPs and Singles');
      expect(line(['Album', 'Other']), 'Albums and Other');
    });

    test('says nothing when no type is allowed', () {
      expect(line(const []), isNull);
    });
  });
}
