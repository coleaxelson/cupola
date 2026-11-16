import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/media_browse_scaffold.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/presentation/media_find_bodies.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/domain/readarr_author_caption.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Authors wall's search of its own library, and its only one: authors by
/// the start of a word of their name, answered as it is typed from the
/// library the wall already read. One section, `3 authors`, of rows with the
/// author's photo in a disc and the caption the wall's tile carries
/// (`3/12 books · 4 missing`).
///
/// Readarr has no lookup any more (its metadata host does not answer), so
/// there is nothing to ask beyond the library and nothing more is offered: an
/// empty answer says only that there is none.
///
/// A tap opens the author as the wall's tile does ([onOpen]).
class AuthorsFindLibrary extends ConsumerWidget {
  const AuthorsFindLibrary({
    super.key,
    required this.query,
    required this.settingsSelector,
    required this.onOpen,
  });

  final String query;

  /// What the wall reads its artwork with (see `MediaBrowseScaffold`).
  final SettingsSelector settingsSelector;

  final void Function(
    BuildContext context,
    ReadarrAuthor author,
    String heroTag,
  )
  onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (baseUrl, apiKey, _) = ref.watch(
      currentSettingsProvider.select(settingsSelector),
    );
    return MediaFindLibraryBody<ReadarrAuthor>(
      query: query,
      library: readarrAuthorsProvider,
      service: ServiceKey.readarr,
      namesOf: (author) => [author.authorName],
      heading: (count) => findCount(count, one: 'author', many: 'authors'),
      rowOf: (context, author) {
        // The photo as the author's page draws it, never a banner.
        final art = ImageUtils.extractPosterUrl(
          author.images,
          baseUrl: baseUrl,
          apiKey: apiKey,
          coverTypes: const ['poster'],
        );
        final tag = 'author_${author.id}_find';
        return SearchRow.disc(
          key: ValueKey(('author', author.id)),
          name: author.authorName,
          line: readarrAuthorCaption(author),
          photo: art.url,
          photoHeaders: art.headers,
          onTap: () => onOpen(context, author, tag),
        );
      },
    );
  }
}
