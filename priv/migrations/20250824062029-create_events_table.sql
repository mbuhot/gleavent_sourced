--- migration:up
CREATE TABLE events (
  sequence_number BIGSERIAL PRIMARY KEY,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_type      TEXT        NOT NULL,
  payload         JSONB       NOT NULL,
  metadata        JSONB       NOT NULL DEFAULT '{}'
);

--- migration:down
DROP TABLE events;

--- migration:end
