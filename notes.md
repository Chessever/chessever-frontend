# Notes: ChessEver Tablet Optimization

## Key Files Reference

### Core Responsive System
- **ResponsiveHelper**: `/lib/utils/responsive_helper.dart`
  - Has `DeviceType` enum (phone, tablet)
  - Uses 600dp threshold for tablet detection
  - Extensions: `.w`, `.h`, `.f`, `.sp`, `.ic`, `.br`
  - **Tablet-specific helpers**: `shouldUseSplitView`, `tabletGridColumns`, `contentMaxWidth`, `adaptive()`

### Theme System
- **AppTheme**: `/lib/theme/app_theme.dart`
- **AppTypography**: `/lib/utils/app_typography.dart`

### Main Entry
- **main.dart**: `/lib/main.dart`

## Comprehensive Screen Analysis (Jan 2026)

### Priority Matrix

| Screen | Current State | Priority | Effort |
|--------|--------------|----------|--------|
| ChessBoardScreen | No split-view | **CRITICAL** | High |
| GamesTourScreen | Minimal tablet | **HIGH** | Medium |
| PlayerTourScreen | No tablet | **HIGH** | Medium |
| FavoritesGamesTab | Partial (2-col) | **MEDIUM** | Low |
| FavoritesListTab | No tablet | **HIGH** | Medium |
| FavoritesPlayersTab | No tablet | **HIGH** | Medium |
| PlayerScreen | No tablet | **HIGH** | Medium |
| LibraryScreen | No tablet | **HIGH** | Medium |
| CalendarScreen | Partial (3-col) | **MEDIUM** | Low |
| CalendarEventDetail | No tablet | **MEDIUM** | Medium |
| AboutTourScreen | No tablet | **LOW** | Low |
| TournamentDetail | No tablet | **LOW** | Medium |

---

## Screen-by-Screen Findings

### 1. ChessBoardScreen (CRITICAL)
**File:** `/lib/screens/chessboard/chess_board_screen_new.dart`

**Current:**
- Complex multi-section layout with board, player info, analysis
- Analysis panels in bottom sheet overlay
- No landscape optimization

**Tablet Optimizations Needed:**
- Split-view: board left (flex 2), analysis right (flex 3) in landscape
- Side panel for analysis instead of bottom sheet
- Constrain board size with max dimensions
- Move evaluation bar to side in landscape
- Player cards horizontal on tablets

### 2. GamesTourScreen (HIGH)
**File:** `/lib/screens/tour_detail/games_tour/views/games_tour_screen.dart`

**Current:**
- Single-column list with round grouping
- Has grid mode but only 2-column pairing
- One adaptive padding reference

**Tablet Optimizations Needed:**
- Use `tabletGridColumns` for 3-4 columns on tablet landscape
- Consider split-view: round selector left, games right
- Apply `contentMaxWidth` constraint

### 3. PlayerTourScreen (HIGH)
**File:** `/lib/screens/tour_detail/player_tour/player_tour_screen.dart`

**Current:**
- Single-column ListView with fixed-width columns
- No tablet conditionals

**Tablet Optimizations Needed:**
- GridView with 2-3 columns on tablet
- Card-based layout instead of row-based
- Adaptive column widths

### 4. Favorites Screens (HIGH)
**Files:**
- `/lib/screens/favorites/favorite_screen.dart`
- `/lib/screens/favorites/tabs/favorites_list_tab.dart`
- `/lib/screens/favorites/tabs/favorites_players_tab.dart`
- `/lib/screens/favorites/tabs/favorites_games_tab.dart`

**Current:**
- FavoritesGamesTab has view toggle (best implemented)
- Others are single-column ListViews

**Tablet Optimizations Needed:**
- Add grid layouts using `getGridCrossAxisCount()`
- 2-3 columns on tablet portrait, 3-4 on landscape
- Card redesign for vertical grid format

### 5. PlayerScreen (HIGH)
**File:** `/lib/screens/players/player_screen.dart`

**Current:**
- Single-column ListView with pagination
- Fixed header widths

**Tablet Optimizations Needed:**
- GridView with adaptive columns
- Max-width constraint
- Adaptive header spacing

### 6. LibraryScreen (HIGH)
**File:** `/lib/screens/library/library_screen.dart`

**Current:**
- SliverList for folders (single column)
- Fixed padding

**Tablet Optimizations Needed:**
- SliverGrid with 2-3 columns
- Adaptive padding
- Max-width constraint

### 7. Calendar Screens (MEDIUM)
**Files:**
- `/lib/screens/calendar/calendar_screen.dart` - Partial tablet (3-col months)
- `/lib/screens/calendar/calendar_detail_screen.dart` - Minimal
- `/lib/screens/calendar/calendar_event_detail_screen.dart` - None

**Tablet Optimizations Needed:**
- CalendarScreen: 4 columns on large landscape
- CalendarDetail: Split-view option
- EventDetail: 2-column layout on landscape

### 8. About/Tournament Screens (LOW)
**Files:**
- `/lib/screens/tour_detail/about_tour_screen.dart`
- `/lib/screens/tour_detail/tournament_detail_screen.dart`

**Tablet Optimizations Needed:**
- AboutTour: 2-column info layout
- TournamentDetail: Persistent nav instead of PageView

---

## Available ResponsiveHelper Methods

```dart
// Device & Orientation
ResponsiveHelper.isTablet              // bool
ResponsiveHelper.isLandscape           // bool
ResponsiveHelper.shouldUseSplitView    // bool (tablet + landscape + min width)

// Grid Helpers
ResponsiveHelper.tabletGridColumns     // int (2-4)
ResponsiveHelper.getGridCrossAxisCount({int phoneCount = 1})
ResponsiveHelper.getCardWidth({double phoneWidth})
ResponsiveHelper.getCardAspectRatio({double phoneRatio})

// Layout Constraints
ResponsiveHelper.contentMaxWidth       // 1200.0
ResponsiveHelper.tabletHorizontalPadding
ResponsiveHelper.splitViewMasterFlex   // 2
ResponsiveHelper.splitViewDetailFlex   // 3

// Adaptive Values
ResponsiveHelper.adaptive<T>(phone: X, tablet: Y)
ResponsiveHelper.adaptiveOrientation<T>(...)
```

---

## Common Patterns to Apply

### Pattern 1: Grid Layout Conversion
```dart
// Before (phone-only)
SliverList(
  delegate: SliverChildBuilderDelegate((ctx, i) => Card(...)),
)

// After (tablet-adaptive)
SliverGrid(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: ResponsiveHelper.getGridCrossAxisCount(),
    crossAxisSpacing: 12.sp,
    mainAxisSpacing: 12.sp,
    childAspectRatio: ResponsiveHelper.getCardAspectRatio(phoneRatio: 3.0),
  ),
  delegate: SliverChildBuilderDelegate((ctx, i) => Card(...)),
)
```

### Pattern 2: Split View
```dart
if (ResponsiveHelper.shouldUseSplitView) {
  return Row(
    children: [
      Expanded(flex: ResponsiveHelper.splitViewMasterFlex, child: master),
      VerticalDivider(width: 1, color: kDarkGreyColor),
      Expanded(flex: ResponsiveHelper.splitViewDetailFlex, child: detail),
    ],
  );
} else {
  return phoneLayout;
}
```

### Pattern 3: Max Width Constraint
```dart
Widget buildContent(Widget child) {
  if (!ResponsiveHelper.isTablet) return child;
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.tabletHorizontalPadding),
        child: child,
      ),
    ),
  );
}
```

---

## Implementation Progress

### Phase 1: Foundation ✅
- [x] ResponsiveHelper extensions
- [x] Landscape orientation support
- [x] TabletNavRail component

### Phase 2: Core Navigation ✅
- [x] HomeScreen tablet layout
- [x] TabletNavRail implementation

### Phase 3: Tournament Screens (In Progress)
- [x] GroupEventScreen
- [ ] TournamentDetailScreen
- [ ] GamesTourScreen
- [ ] PlayerTourScreen
- [ ] AboutTourScreen

### Phase 4-11: Pending
(See task_plan.md for full checklist)
