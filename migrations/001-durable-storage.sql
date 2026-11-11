-- Private game-server documents. No browser or APK connects to PostgreSQL.
CREATE TABLE IF NOT EXISTS quartiers_documents (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- The newest server owns writes during overlapping Render deployments.
CREATE TABLE IF NOT EXISTS quartiers_writer (
    id boolean PRIMARY KEY DEFAULT true CHECK (id),
    generation bigint NOT NULL
);
