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

-- name: ReadEventsWithFactTags :many
WITH filter_conditions AS (
  SELECT
    filter_config ->> 'fact_id' as fact_id,
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
),
events_with_tags AS (
  SELECT
    e.*,
    ARRAY(
      SELECT fc.fact_id
      FROM filter_conditions fc
      WHERE fc.event_type = e.event_type
        AND jsonb_path_exists(e.payload, fc.jsonpath_expr::jsonpath, fc.jsonpath_params)
    ) as matching_facts
  FROM matching_events e
)
SELECT
  *,
  matching_facts,
  (SELECT MAX(sequence_number) FROM matching_events)::integer as current_max_sequence
FROM events_with_tags
ORDER BY sequence_number ASC;

-- name: BatchInsertEventsWithConflictCheck :one
WITH filter_conditions AS (
  SELECT
    filter_config ->> 'event_type' as event_type,
    filter_config ->> 'filter' as jsonpath_expr,
    filter_config -> 'params' as jsonpath_params
  FROM jsonb_array_elements(@conflict_filter) AS filter_config
),
conflict_check (conflict_count) AS (
  SELECT
    COUNT(*) as conflict_count
  FROM events e
  JOIN filter_conditions fc ON e.event_type = fc.event_type
  WHERE jsonb_path_exists(e.payload, fc.jsonpath_expr::jsonpath, fc.jsonpath_params)
    AND e.sequence_number > @last_seen_sequence
),
new_events_parsed AS (
  SELECT
    event_data ->> 'type' as event_type,
    event_data -> 'data' as event_data,
    event_data -> 'metadata' as metadata
  FROM jsonb_array_elements(@events) AS event_data
),
insert_result AS (
  INSERT INTO events (event_type, payload, metadata)
  SELECT event_type, event_data, metadata
  FROM new_events_parsed
  WHERE (SELECT conflict_count FROM conflict_check) = 0
  RETURNING sequence_number
)
SELECT
  CASE
    WHEN EXISTS(SELECT 1 FROM insert_result) THEN 'success'
    ELSE 'conflict'
  END as status,
  (SELECT conflict_count FROM conflict_check) as conflict_count;
