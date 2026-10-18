-- Example setup. Generate each secret yourself, for example:  openssl rand -hex 32
-- The secret must match the one you configure at the provider (GitHub, Stripe, your own service).

-- INSERT INTO sources (name, scheme, secret) VALUES ('github', 'github', '<64 hex chars>');
-- INSERT INTO destinations (source, name, url, secret)
--   VALUES ('github', 'ci-service', 'https://ci.example.com/hooks/github', '<another secret, optional>');

-- Stripe: scheme 'stripe', use the endpoint's signing secret (whsec_...).
-- Your own services: scheme 'generic' (X-Signature + X-Timestamp, see README).

-- Disable a destination without deleting history:
-- UPDATE destinations SET enabled = FALSE WHERE id = 1;
