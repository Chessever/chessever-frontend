# liquid_glass_widgets — full public surface → Chessever usage

Import path for modernized screens: `package:chessever2/widgets/liquid_glass/glass_kit.dart`

## Setup (required)
| Package API | App wiring |
|-------------|------------|
| `LiquidGlassWidgets.initialize()` | `lib/main.dart` |
| `LiquidGlassWidgets.wrap(theme:…)` | `_buildRootApp()` light/dark `GlassThemeData` |
| `GlassScaffold` | Home phone shell |
| `GlassPage` | `ScreenWrapper` on secondary shells |
| `contentAwareBrightness` | Home `GlassScaffold` |

## Surfaces / chrome
| Package | Adapter / call sites |
|---------|----------------------|
| `GlassTabBar.searchable` + `GlassSearchBarConfig` | Home bottom nav morph |
| `GlassTab` / `GlassSegment` | Nav + segmented switcher |
| `GlassSegmentedControl` | `SegmentedSwitcher` |
| `GlassAppBar` | `GlassDetailAppBar` |
| `GlassIconButton` | `GlassBackButton`, avatar, filter, library actions |
| `GlassChip` | Single-option segmented fallback |
| `GlassSearchBar` | Expanded `GlassIslandSearch` |
| `GlassBadge` | Events filter count |
| `GlassToolbar` | Available via kit for action bars |
| `GlassLargeTitle` | Available via kit for collapse titles |

## Containers
| Package | Usage |
|---------|--------|
| `GlassContainer` | Low-level (prefer card/section) |
| `GlassCard` | Dialogs/sheets internally |
| `GlassListTile` / `.standalone` | Settings appearance |
| `GlassGroupedSection` | Settings sections (when no nested interactive glass) |
| `GlassDivider` | Between list tiles |
| `GlassStepper` | Available via kit |

## Interactive / input
| Package | Usage |
|---------|--------|
| `GlassSwitch` | Settings light mode (sibling of list tile, not nested) |
| `GlassButton` / `GlassButtonGroup` | Dialogs / toolbars |
| `GlassSlider` / `GlassPullDownButton` / `GlassPicker` | Available via kit |
| `GlassTextField` / `GlassTextArea` / `GlassPasswordField` / `GlassFormField` | Available via kit |
| `GlassPageControl` | Available via kit |

## Overlays / feedback
| Package | Adapter |
|---------|---------|
| `GlassToast` | `showGlassSnack` |
| `GlassDialog` | `showGlassConfirmDialog` |
| `GlassSheet` | `showAppGlassSheet` |
| `showGlassActionSheet` | `showAppGlassActionSheet` |
| `GlassModalSheet` / `GlassPopover` / `GlassMenu` | Available via kit |
| `GlassProgressIndicator` | `GlassLoading` |

## Motion stack (cue + motor + liquid_glass)
| Layer | Role |
|-------|------|
| **cue** `Cue.onToggle` + `Act.sizedClip` / `Act.scale` | Boolean morphs: search widen forward / snappy back; shell pulse |
| **motor** `SingleMotionBuilder` + `CupertinoMotion` | Continuous values: scroll-chrome scale, shell scale settle |
| **liquid_glass** `springDescription` on `GlassTabBar.searchable` | Package pill morph physics (`GlassMotion.searchMorphSpring`) |

Presets live in `glass_motion.dart`. Island search uses cue sizedClip (expand from trailing edge); bottom nav uses package morph spring + motor scroll scale + cue shell pulse.

## Composition rules (enforced)
1. Glass = control layer only; content stays opaque.
2. Never put `GlassSwitch` / `GlassButton` / `GlassSegmentedControl` / `GlassChip` inside `GlassCard` / `GlassContainer` / `GlassGroupedSection`.
3. Standalone interactive glass uses `useOwnLayer: true`.
4. Prefer package widgets over custom glass reimplementations.
