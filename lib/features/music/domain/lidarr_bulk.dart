import 'package:cupola/core/api/arr_bulk.dart';

/// What `PUT /api/v1/artist/editor` is asked to set on a set of artists: the
/// arrs' shared edit (`ArrBulkEdit`), with Lidarr's `monitorNewItems` and
/// metadata profile.
typedef LidarrArtistEdit = ArrBulkEdit;

/// What Lidarr said of a set of artists a write was for.
typedef LidarrBulkResult = ArrBulkResult;
