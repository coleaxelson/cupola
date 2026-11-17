import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:cupola/core/app_spacing.dart';

/// Where the screen folds, and how far a control keeps from it.
///
/// A foldable opened flat is one screen with a crease down its middle. A
/// switch or a button on the crease is hard to see and harder to press, so a
/// control that would sit on it moves to one side ([ClearOfFold]); a dialog
/// opens in one half of its own accord (Flutter's `DisplayFeatureSubScreen`).
///
/// Both read the fold from [MediaQuery.displayFeaturesOf]. Android's embedder
/// fills that in itself; iOS's does not, so [FoldHost] does it from the
/// native side's answer (`cupola/fold`, `AppDelegate.swift`).
abstract final class Fold {
  /// How far a control stays from the fold.
  static const double clearance = AppSpacing.lg;

  /// The x of a fold or hinge running top to bottom across [context]'s view,
  /// in global coordinates, or null when there is none.
  static double? verticalOf(BuildContext context) {
    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if (feature.type == DisplayFeatureType.cutout) continue;
      final bounds = feature.bounds;
      if (bounds.height > bounds.width) return bounds.center.dx;
    }
    return null;
  }
}

/// Publishes the fold the iOS side reports as a [DisplayFeature], so the rest
/// of the app reads one answer on every platform, and widens every fold to
/// the band controls keep out of.
///
/// Above the router, under `MaterialApp`'s own [MediaQuery]. Listens to the
/// native side on iOS only; where the platform reports a fold itself
/// (Android), that one is kept and only widened.
class FoldHost extends StatefulWidget {
  const FoldHost({super.key, required this.child});

  final Widget child;

  @visibleForTesting
  static const channel = MethodChannel('cupola/fold');

  @override
  State<FoldHost> createState() => _FoldHostState();
}

class _FoldHostState extends State<FoldHost> {
  DisplayFeature? _fold;

  static bool get _listens =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_listens) return;
    FoldHost.channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _take(call.arguments);
    });
    FoldHost.channel
        .invokeMethod<Object?>('current')
        .then(_take)
        // No native side (a test, an older OS): no fold to report.
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    if (_listens) FoldHost.channel.setMethodCallHandler(null);
    super.dispose();
  }

  void _take(Object? answer) {
    if (!mounted) return;
    final fold = _parse(answer);
    if (fold?.bounds == _fold?.bounds && fold?.state == _fold?.state) return;
    setState(() => _fold = fold);
  }

  static DisplayFeature? _parse(Object? answer) {
    if (answer is! Map) return null;
    final at = (answer['at'] as num?)?.toDouble();
    final from = (answer['from'] as num?)?.toDouble();
    final to = (answer['to'] as num?)?.toDouble();
    if (at == null || from == null || to == null) return null;
    final vertical = answer['axis'] == 'vertical';
    return DisplayFeature(
      bounds: vertical
          ? Rect.fromLTRB(at, from, at, to)
          : Rect.fromLTRB(from, at, to, at),
      type: DisplayFeatureType.fold,
      state: answer['flat'] == true
          ? DisplayFeatureState.postureFlat
          : DisplayFeatureState.postureHalfOpened,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reported = media.displayFeatures.any(_isCrease);
    final native = _fold;
    final features = [
      ...media.displayFeatures,
      if (native != null && !reported) native,
    ];
    if (!features.any(_isCrease)) return widget.child;
    return MediaQuery(
      data: media.copyWith(
        displayFeatures: [for (final f in features) _kept(f)],
      ),
      child: widget.child,
    );
  }

  static bool _isCrease(DisplayFeature feature) =>
      feature.type != DisplayFeatureType.cutout;

  /// A fold reported as a line, as a flat one is on every platform, widened
  /// to the band a control keeps out of ([Fold.clearance] each side). Flutter
  /// leaves a line alone, so a dialog would open across the crease; a band it
  /// opens beside, in one half.
  static DisplayFeature _kept(DisplayFeature feature) {
    if (!_isCrease(feature)) return feature;
    final b = feature.bounds;
    if (b.width > 0 && b.height > 0) return feature;
    const c = Fold.clearance;
    return DisplayFeature(
      bounds: b.width == 0
          ? Rect.fromLTRB(b.left - c, b.top, b.right + c, b.bottom)
          : Rect.fromLTRB(b.left, b.top - c, b.right, b.bottom + c),
      type: feature.type,
      state: feature.state,
    );
  }
}

/// Lets [child] grow to [maxWidth], but stops it short of a fold running
/// down the screen when it would otherwise cross it: a row whose control sits
/// at its far end keeps that control on the near side of the crease.
///
/// Where the child sits is known only once it is laid out, so the first frame
/// on a new fold draws it as it was and the next one moves it: a frame, at the
/// moment the device unfolds, when the whole page is moving anyway.
class ClearOfFold extends StatefulWidget {
  const ClearOfFold({super.key, required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  State<ClearOfFold> createState() => _ClearOfFoldState();
}

class _ClearOfFoldState extends State<ClearOfFold> {
  double? _limit;

  void _measure(double? foldX) {
    if (!mounted) return;
    final box = context.findRenderObject();
    double? limit;
    if (foldX != null && box is RenderBox && box.hasSize && box.attached) {
      final left = box.localToGlobal(Offset.zero).dx;
      final stop = foldX - Fold.clearance;
      if (left < stop && left + widget.maxWidth > stop) limit = stop - left;
    }
    if (limit != _limit) setState(() => _limit = limit);
  }

  @override
  Widget build(BuildContext context) {
    final foldX = Fold.verticalOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure(foldX));
    final limit = _limit;
    final width = limit == null || limit > widget.maxWidth
        ? widget.maxWidth
        : limit;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: widget.child,
    );
  }
}
