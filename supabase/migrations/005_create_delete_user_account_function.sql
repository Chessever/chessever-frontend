-- Function to delete user account (called from client)
-- Uses SECURITY DEFINER to run with elevated privileges needed to delete from auth.users
-- All user data tables have CASCADE delete on user_id FK, so deleting from auth.users
-- will automatically clean up: user_favorite_events, user_favorite_players,
-- user_engine_settings, user_folders, user_saved_analyses

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  -- Get the current user's ID from the JWT
  current_user_id := auth.uid();

  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Delete the user from auth.users
  -- This will CASCADE delete all related data in:
  -- - user_favorite_events
  -- - user_favorite_players
  -- - user_engine_settings
  -- - user_folders
  -- - user_saved_analyses
  DELETE FROM auth.users WHERE id = current_user_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
