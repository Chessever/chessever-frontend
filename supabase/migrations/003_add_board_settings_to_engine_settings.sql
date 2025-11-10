-- Add board settings and engine visibility columns to existing user_engine_settings table
-- This consolidates all user settings into one table

-- Add board settings columns
ALTER TABLE public.user_engine_settings
ADD COLUMN IF NOT EXISTS board_color_index INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS show_evaluation_bar BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS sound_enabled BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS chat_enabled BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS piece_style_index INTEGER NOT NULL DEFAULT 0;

-- Add engine visibility column
ALTER TABLE public.user_engine_settings
ADD COLUMN IF NOT EXISTS show_engine_analysis BOOLEAN NOT NULL DEFAULT true;

-- Add constraints for board_color_index (0-3 for Default/Brown/Grey/Green)
ALTER TABLE public.user_engine_settings
DROP CONSTRAINT IF EXISTS board_color_index_check;

ALTER TABLE public.user_engine_settings
ADD CONSTRAINT board_color_index_check CHECK (board_color_index >= 0 AND board_color_index <= 3);

-- Add constraints for piece_style_index (0-4 for different piece styles)
ALTER TABLE public.user_engine_settings
DROP CONSTRAINT IF EXISTS piece_style_index_check;

ALTER TABLE public.user_engine_settings
ADD CONSTRAINT piece_style_index_check CHECK (piece_style_index >= 0 AND piece_style_index <= 4);

-- Update the trigger comment to reflect new columns
COMMENT ON TABLE public.user_engine_settings IS 'Stores all user settings: engine configuration, board appearance, and UI preferences';
