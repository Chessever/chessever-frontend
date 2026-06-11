-- PiP / Live Activity settings dropped the "all" (2) option; only off(0)/live(1)
-- remain. Collapse any legacy "all" rows down to "live" so those users stay
-- opted in instead of silently falling back to off.
update user_engine_settings set pip_mode = 1 where pip_mode = 2;
update user_engine_settings set live_activity_mode = 1 where live_activity_mode = 2;
