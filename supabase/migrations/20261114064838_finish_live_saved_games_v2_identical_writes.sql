-- Production applied finish_live_saved_game's "an identical game is not
-- written again" change as its own migration after v2. The repo's v2 file
-- (20261114064616) already carries the final function, so nothing is left
-- to do here; the file keeps the repo's history in step with production's.
select 1;
