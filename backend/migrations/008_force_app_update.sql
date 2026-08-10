-- Force-update policy controlled from admin (Supasoka-style).
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS force_update_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS min_android_build int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS min_android_version text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS latest_android_version text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS latest_android_build int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS play_store_url text NOT NULL DEFAULT 'https://play.google.com/store/apps/details?id=com.washatv',
  ADD COLUMN IF NOT EXISTS update_title text NOT NULL DEFAULT 'Sasisha WASHA TV',
  ADD COLUMN IF NOT EXISTS update_message text NOT NULL DEFAULT 'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.';
