/// Library-related constants and utility functions.
///
/// This file contains shared constants and helper methods used across
/// library-related screens and widgets.
library;

/// Maximum number of books/folders a free user can create.
/// After reaching this limit, users must upgrade to premium.
const int kFreeBookCreationLimit = 3;

/// Maximum number of saved games a free user can keep across all databases.
/// Counted as total rows in `user_saved_analyses` for the user — not per folder.
const int kFreeSavedGamesLimit = 10;
