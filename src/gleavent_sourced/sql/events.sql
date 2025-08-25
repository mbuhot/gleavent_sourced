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

-- name: ReadEventsWithFilter :many
WITH filter_conditions AS (
  SELECT
    filter_config ->> 'event_type' as event_type,
    filter_config ->> 'filter' as jsonpath_expr,
    filter_config -> 'params' as jsonpath_params
  FROM jsonb_array_elements(@filters) AS filter_config
),
matching_events AS (
  SELECT DISTINCT e.*
  FROM events e
  JOIN filter_conditions fc ON e.event_type = fc.event_type
  WHERE jsonb_path_exists(e.payload, fc.jsonpath_expr::jsonpath, fc.jsonpath_params)
)
SELECT
  *,
  (SELECT MAX(sequence_number) FROM matching_events)::integer as current_max_sequence
FROM matching_events
ORDER BY sequence_number ASC;
