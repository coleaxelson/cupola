import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';

/// `3/12 books · 4 missing`: the caption under an author's portrait.
///
/// Top-level and pure so the wording is assertable without a pumped wall, as
/// `lidarrArtistCaption` is. The counts are the ones the row has always shown;
/// the missing part is left out when nothing is.
///
/// An author with no book counted reads an em dash. Readarr's `statistics`
/// can be absent (an author it has not scanned yet) and the model reads an
/// absent count as zero, so `0/0 books` would assert a fact nobody reported.
String readarrAuthorCaption(ReadarrAuthor author) {
  if (author.bookCount <= 0) return Lexicon.noFigure;
  return [
    '${author.bookFileCount}/${author.bookCount}$unitSpace'
        'books',
    if (author.missingBookCount > 0)
      '${author.missingBookCount} ${StateWord.missing.inline}',
  ].join(dotSeparator);
}
