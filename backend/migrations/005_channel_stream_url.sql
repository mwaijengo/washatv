-- Playback URL for each channel (HLS, m3u8, mp4, etc.)

ALTER TABLE channels
  ADD COLUMN IF NOT EXISTS stream_url text NOT NULL DEFAULT '';
