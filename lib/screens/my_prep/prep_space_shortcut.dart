import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';

/// Pins the saved profile itself, so online-only and imported profiles open
/// with the same combined sources as they do in My Prep.
SpaceShortcut prepProfileSpaceDraft(PrepProfile profile) => SpaceShortcut.draft(
  kind: SpaceShortcutKind.prepProfile,
  targetId: profile.id,
  title: profile.name,
  subtitle: 'My Prep',
);
