import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/domain/artist_track_find.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/music/presentation/artist_page_providers.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Finds a track among an artist's albums, in the place of the page's albums
/// while it is open: a field, the tracks the words typed open, and what to
/// say when there are none yet.
///
/// Lidarr lists tracks under albums, so the tracks of the whole artist are read
/// once (`GET /api/v1/track?artistId=`, [lidarrArtistTracksProvider]) when the
/// finder first opens, and matched here as the words are typed (word prefix,
/// blind to case and accents). A row names the track, its album and its place
/// on it, and says `On disk` or where its album stands, so a track never
/// contradicts its album; a tap hands the album to [onOpenAlbum], which
/// closes the finder and lands the page on that album's tracks.
///
/// A sliver: it stands among the page's slivers where the albums stood.
class ArtistTrackFinder extends ConsumerStatefulWidget {
  const ArtistTrackFinder({
    super.key,
    required this.artistName,
    required this.record,
    required this.albums,
    required this.queue,
    required this.now,
    required this.coverOf,
    required this.onOpenAlbum,
    required this.onClose,
  });

  final String artistName;

  /// The artist, on the connection the page belongs to.
  final LidarrRecordRef record;

  /// The albums the page holds: the tracks are found on these.
  final List<LidarrAlbum> albums;

  /// The queue of albums, for the word of an album a track is not on disk
  /// from; its word waits while the queue is being read.
  final ArrQueueSnapshot queue;
  final DateTime now;

  /// An album's cover, or null for the initials.
  final ShelfArt? Function(LidarrAlbum album) coverOf;

  final ValueChanged<LidarrAlbum> onOpenAlbum;

  /// Done, or the field cleared and left: the pills come back.
  final VoidCallback onClose;

  @override
  ConsumerState<ArtistTrackFinder> createState() => _ArtistTrackFinderState();
}

class _ArtistTrackFinderState extends ConsumerState<ArtistTrackFinder> {
  final _focus = FocusNode(debugLabel: 'find a track');
  var _query = '';

  /// The index of the tracks and albums it was built from: a keystroke
  /// searches it, and only a new read builds another.
  ArtistTrackIndex? _index;
  List<LidarrTrack>? _indexedTracks;
  List<LidarrAlbum>? _indexedAlbums;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  /// Leaving the field with nothing typed is leaving the finder.
  void _onFocus() {
    if (!_focus.hasFocus && _query.isEmpty) widget.onClose();
  }

  ArtistTrackIndex _indexFor(List<LidarrTrack> tracks) {
    if (_index == null ||
        !identical(tracks, _indexedTracks) ||
        !identical(widget.albums, _indexedAlbums)) {
      _indexedTracks = tracks;
      _indexedAlbums = widget.albums;
      _index = ArtistTrackIndex(tracks: tracks, albums: widget.albums);
    }
    return _index!;
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final tracks = ref.watch(lidarrArtistTracksProvider(widget.record));
    final caption = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          'Tracks of ${widget.artistName}’s albums that Lidarr knows. '
          'A tap opens the album on its tracks.',
          style: AppType.caption.copyWith(color: room.inkTertiary),
        ),
      ),
    );
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SearchBarHeader(
            label: 'Find a track by ${widget.artistName}',
            hintText: 'Find a track by ${widget.artistName}',
            autofocus: true,
            focusNode: _focus,
            cancelLabel: 'Done',
            padding: const EdgeInsets.only(
              top: AppSpacing.lg,
              bottom: AppSpacing.xs,
            ),
            onQueryChanged: (_) {},
            onTextChanged: (query) => setState(() => _query = query),
            onCancel: widget.onClose,
          ),
        ),
        ...switch (tracks) {
          AsyncValue(:final value?) => _results(_indexFor(value), caption),
          AsyncValue(:final error?) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: InlineErrorRetry(
                  message: sectionFailureMessage(
                    ServiceKey.lidarr,
                    error,
                    consequence: 'its tracks cannot be searched',
                  ),
                  error: error,
                  service: ServiceKey.lidarr,
                  instanceId: widget.record.instanceId,
                  onRetry: () =>
                      ref.invalidate(lidarrArtistTracksProvider(widget.record)),
                ),
              ),
            ),
          ],
          _ => const [
            SliverToBoxAdapter(
              child: ExcludeSemantics(
                child: SearchHeading('Asking Lidarr', top: AppSpacing.lg),
              ),
            ),
            SliverToBoxAdapter(
              child: SearchRowsPending(
                label: 'Asking Lidarr',
                rows: 3,
                shape: SearchRowsShape.square,
              ),
            ),
          ],
        },
      ],
    );
  }

  List<Widget> _results(ArtistTrackIndex index, Widget caption) {
    if (_query.isEmpty) return [caption];
    final hits = index.find(_query);
    if (hits.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SearchNothing(
            title: 'No track called “$_query”',
            message:
                'Lidarr knows the tracks of the albums it lists for this '
                'artist.',
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: SearchHeading(trackCountWords(hits.length), top: AppSpacing.lg),
      ),
      ShelfSliverGroup(
        itemCount: hits.length,
        itemBuilder: (context, i) => _row(hits[i]),
      ),
      caption,
    ];
  }

  Widget _row(ArtistTrackHit hit) {
    final track = hit.track;
    final album = hit.album;
    final state = trackState(
      track,
      album,
      queue: widget.queue,
      now: widget.now,
    );
    final art = widget.coverOf(album);
    return SearchRow.album(
      key: ValueKey(('track', track.id)),
      title: track.title,
      titleMarks: hit.marks,
      coverName: album.title,
      meta: trackMeta(track, album),
      status: state == null ? null : (label: state.word, tone: state.tone),
      statusHollow: state?.hollow ?? false,
      cover: art?.url ?? '',
      coverHeaders: art?.headers,
      spoken: trackSpoken(track, album, state: state),
      hint: 'Opens ${album.title} on its tracks',
      onTap: () => widget.onOpenAlbum(album),
    );
  }
}
