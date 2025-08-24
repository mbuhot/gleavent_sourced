-- name: AppendEvent :exec
INSERT INTO events (event_type, payload, metadata)
VALUES ($1, $2, $3);

-- name: ReadAllEvents :many
SELECT sequence_number, occurred_at, event_type, payload, metadata
FROM events
ORDER BY sequence_number;

-- name: ReadEventsByTypes :many
SELECT sequence_number, occurred_at, event_type, payload, metadata
FROM events
WHERE event_type = ANY(@event_types::text[])
ORDER BY sequence_number;
