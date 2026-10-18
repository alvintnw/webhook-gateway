-- Webhook Gateway schema (PostgreSQL 13+). Safe to run twice.

CREATE TABLE IF NOT EXISTS sources (
  name              TEXT PRIMARY KEY CHECK (name ~ '^[a-z0-9_-]{1,40}$'),
  scheme            TEXT NOT NULL CHECK (scheme IN ('github', 'stripe', 'generic')),
  secret            TEXT NOT NULL CHECK (length(secret) >= 16 AND secret !~* '^replace'),
  tolerance_seconds INT  NOT NULL DEFAULT 300 CHECK (tolerance_seconds BETWEEN 30 AND 86400),
  enabled           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS destinations (
  id         SERIAL PRIMARY KEY,
  source     TEXT NOT NULL REFERENCES sources(name) ON UPDATE CASCADE ON DELETE CASCADE,
  name       TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  url        TEXT NOT NULL CHECK (url ~* '^https?://[^\s]+$'),
  secret     TEXT CHECK (secret IS NULL OR length(secret) >= 16),   -- optional: sign outgoing requests
  enabled    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, url)
);

CREATE TABLE IF NOT EXISTS events (
  id           BIGSERIAL PRIMARY KEY,
  source       TEXT NOT NULL REFERENCES sources(name) ON UPDATE CASCADE ON DELETE CASCADE,
  event_id     TEXT NOT NULL CHECK (event_id ~ '^[A-Za-z0-9_.:-]{1,100}$'),
  event_type   TEXT CHECK (event_type IS NULL OR event_type ~ '^[A-Za-z0-9_.:-]{1,60}$'),
  content_type TEXT NOT NULL DEFAULT 'application/json',
  body         TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 1000000),
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, event_id)                      -- idempotency: a provider retry is stored once
);
CREATE INDEX IF NOT EXISTS events_received_idx ON events (received_at);

CREATE TABLE IF NOT EXISTS deliveries (
  id              BIGSERIAL PRIMARY KEY,
  event_id        BIGINT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  destination_id  INT    NOT NULL REFERENCES destinations(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'delivering', 'retrying', 'delivered', 'dead')),
  attempts        INT  NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_until    TIMESTAMPTZ,
  last_status     INT,
  last_error      TEXT,
  delivered_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, destination_id)
);
CREATE INDEX IF NOT EXISTS deliveries_due_idx ON deliveries (status, next_attempt_at);

CREATE TABLE IF NOT EXISTS rejections (
  id         BIGSERIAL PRIMARY KEY,
  source     TEXT,
  reason     TEXT,
  ip         TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rejections_created_idx ON rejections (created_at);

-- Quick overview of the queue
CREATE OR REPLACE VIEW delivery_stats AS
SELECT e.source, d.status, COUNT(*)::int AS deliveries, MIN(d.next_attempt_at) AS oldest_due
FROM deliveries d JOIN events e ON e.id = d.event_id
GROUP BY e.source, d.status;
