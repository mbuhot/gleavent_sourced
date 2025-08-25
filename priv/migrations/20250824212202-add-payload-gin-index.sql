--- migration:up
CREATE INDEX idx_events_payload_gin ON events USING gin (payload);

--- migration:down
DROP INDEX idx_events_payload_gin;

--- migration:end
