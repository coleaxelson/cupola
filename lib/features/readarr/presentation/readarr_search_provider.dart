// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

/// The word typed into the Authors search field.
///
/// What it finds is the library's own, on purpose, and is drawn by
/// `AuthorsFindLibrary`: Lidarr's field asks its server to look an artist up,
/// and Readarr's lookup answers from a metadata host that no longer exists
/// (the project is archived upstream), so a field that did the same would
/// search nothing. What can be found is what Readarr holds, and the whole
/// library is already in hand.
final readarrSearchQueryProvider = StateProvider<String>((ref) => '');
