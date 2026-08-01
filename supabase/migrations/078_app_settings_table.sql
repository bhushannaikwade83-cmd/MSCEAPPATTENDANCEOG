-- Migration: Generic app_settings key/value store
-- Purpose: Let backend-tunable values (e.g. face similarity threshold) be
-- changed from a live admin UI without redeploying Railway.

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app_settings (key, value)
VALUES ('similarity_threshold', '0.70')
ON CONFLICT (key) DO NOTHING;
