-- ClearKey payload for channels using drm = 'clearkey' (hex kid:key, JSON, etc.)
ALTER TABLE channels
  ADD COLUMN IF NOT EXISTS drm_clear_key text NOT NULL DEFAULT '';
