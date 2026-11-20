/// One search mode for every list with a floating search button.
///
/// A page wraps its `Scaffold` in a [SearchModeHost] fed by a
/// [SearchModeController], puts a [SearchModeHeaderSlot] (its own header and
/// a [SearchModeHeader]) inside its `CollapsingChrome`, and floats the
/// [SearchInkFab] (alone or in an `InkFabStack`). The host owns the rest:
/// the searching flag, one spring timeline for the morph both ways, system
/// back, focus and keyboard, holding the scroll chrome while typing, the
/// query (debounced) and clearing it on close.
///
/// The lists under it end in a [SearchModeListEnd]: the room left for the
/// floating buttons gives way, and comes back, on the morph's own timeline.
///
/// See the adoption guide on [SearchModeHost].
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView, lerpDouble;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/home_top_bar.dart'
    show HomeSearchFieldSurface;
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/search_motion.dart' show SearchMotion;
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart'
    show EventSearchBarFrame;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:motor/motor.dart';

export 'search_count_badge.dart';
export 'search_mode_filter_button.dart';

part 'search_mode_controller.dart';
part 'search_mode_host.dart';
part 'search_mode_flight.dart';
part 'search_mode_header.dart';
part 'search_mode_slot.dart';
part 'search_mode_list_end.dart';
