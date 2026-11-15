import 'package:flutter/foundation.dart';

/// A paginated admin list together with the truth about how much of it arrived.
/// A later page can fail after the first one has rendered useful rows; callers
/// must keep those rows, but they must not present them as the complete list.
@immutable
class SeerrAdminResult<T> {
  const SeerrAdminResult({
    required this.items,
    required this.total,
    this.isPartial = false,
  });

  final List<T> items;
  final int total;
  final bool isPartial;
}

@immutable
class SeerrUser {
  const SeerrUser({
    required this.id,
    this.email,
    this.username,
    this.plexUsername,
    this.jellyfinUsername,
    this.serverDisplayName,
    this.avatar,
    this.userType,
    this.permissions,
    this.requestCount,
    this.createdAt,
  });

  final int id;
  final String? email;
  final String? username;
  final String? plexUsername;
  final String? jellyfinUsername;

  /// Seerr's own `displayName`: it computes username, plexUsername,
  /// jellyfinUsername, email in that order, so it is the name of a Jellyfin
  /// or Emby account that has no username.
  final String? serverDisplayName;
  final String? avatar;
  final int? userType;
  final int? permissions;
  final int? requestCount;
  final String? createdAt;

  factory SeerrUser.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return SeerrUser(
      id: _int(json['id']) ?? 0,
      email: _text(json['email']),
      username: _text(json['username']),
      plexUsername: _text(json['plexUsername'] ?? json['plex_username']),
      jellyfinUsername: _text(
        json['jellyfinUsername'] ?? json['jellyfin_username'],
      ),
      serverDisplayName: _text(json['displayName'] ?? json['display_name']),
      avatar: _text(json['avatar']),
      userType: _int(json['userType'] ?? json['user_type']),
      permissions: _int(json['permissions']),
      requestCount: _int(json['requestCount'] ?? json['request_count']),
      createdAt: _text(json['createdAt'] ?? json['created_at']),
    );
  }

  String get displayName {
    for (final value in [
      serverDisplayName,
      username,
      plexUsername,
      jellyfinUsername,
      email,
    ]) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return 'Unnamed user';
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
