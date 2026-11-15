@Tags(['catalog'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/fake_api_client.dart';
import '../test_helpers/fixtures.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// Seerr as the Issues tab meets it: the real shape of its issue list (no
/// title anywhere in `media`), then one read per title page. A title mapped to
/// null does not answer.
class _Seerr extends FakeApiClient {
  _Seerr(this.titles);

  final Map<String, Map<String, dynamic>?> titles;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    final body = path == '/api/v1/issue'
        ? jsonFixtureMap('seerr/issues.json')
        : titles[path];
    if (body == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.receiveTimeout,
      );
    }
    return Response(
      requestOptions: RequestOptions(path: path),
      data: body,
    );
  }
}

const _allNamed = {
  '/api/v1/movie/550': {
    'title': 'Fight Club',
    'posterPath': CatalogArt.tmdbPoster,
  },
  '/api/v1/tv/1399': {
    'name': 'Game of Thrones',
    'posterPath': CatalogArt.tmdbPoster,
  },
  '/api/v1/movie/603': {
    'title': 'The Matrix',
    'posterPath': CatalogArt.tmdbPoster,
  },
};

List<Override> _seerr(Map<String, Map<String, dynamic>?> titles) => [
  seerrServiceProvider.overrideWith(
    (ref) => SeerrService(_Seerr(titles), numbering: SeerrNumbering.seerr),
  ),
];

void main() {
  catalogCard(
    'SeerrIssues',
    overrides: () => settingsScopeOverrides(configured: [ServiceKey.seerr]),
    scenes: [
      CatalogScene(
        'SeerrIssuesScreen() · the Issues tab: each row named from its '
        "title's own page, since Seerr's list carries no title",
        (_) => const SeerrIssuesScreen(),
        width: 390,
        height: 640,
        overrides: _seerr(_allNamed),
      ),
      CatalogScene(
        'SeerrIssuesScreen() · a title that did not answer keeps its row as '
        'it was, Unknown media, the others named',
        (_) => const SeerrIssuesScreen(),
        width: 390,
        height: 640,
        overrides: _seerr({..._allNamed, '/api/v1/tv/1399': null}),
      ),
      CatalogScene(
        'SeerrIssuesScreen() · at twice the reading size',
        (_) => const SeerrIssuesScreen(),
        width: 390,
        height: 900,
        textScale: catalogTextScale,
        overrides: _seerr(_allNamed),
      ),
    ],
  );
}
