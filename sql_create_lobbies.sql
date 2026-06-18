-- Rulează asta în SQL Editor din Supabase Dashboard
CREATE TABLE IF NOT EXISTS lobbies (
  id TEXT PRIMARY KEY,
  host_name TEXT NOT NULL DEFAULT 'Unnamed',
  ip TEXT NOT NULL DEFAULT '0.0.0.0',
  port INTEGER NOT NULL DEFAULT 8912,
  has_password BOOLEAN NOT NULL DEFAULT false,
  player_count INTEGER NOT NULL DEFAULT 1,
  max_players INTEGER NOT NULL DEFAULT 8,
  version TEXT NOT NULL DEFAULT '1.0',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Index pentru query rapid după updated_at
CREATE INDEX IF NOT EXISTS idx_lobbies_updated ON lobbies(updated_at);

-- Funcție de cleanup: șterge lobby-urile mai vechi de 30s
-- Rulează separat în Supabase SQL Editor (sau ca pg_cron job):
--   SELECT cleanup_stale_lobbies();
CREATE OR REPLACE FUNCTION cleanup_stale_lobbies()
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM lobbies WHERE updated_at < NOW() - INTERVAL '30 seconds';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;
