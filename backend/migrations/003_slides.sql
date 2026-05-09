-- Hero / carousel slides for public bootstrap (admin CRUD).

CREATE TABLE IF NOT EXISTS slides (
  id text PRIMARY KEY,
  title text NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  image_url text NOT NULL,
  premium boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_slides_active_sort ON slides (active, sort_order, id);
CREATE INDEX IF NOT EXISTS idx_slides_sort ON slides (sort_order, id);
