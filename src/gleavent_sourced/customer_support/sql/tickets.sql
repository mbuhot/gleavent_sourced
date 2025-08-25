-- name: ReadEventsForTicketCommandContext :many
SELECT sequence_number, occurred_at, event_type, payload, metadata
FROM events
WHERE (event_type = 'TicketOpened' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketAssigned' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketClosed' AND payload->>'ticket_id' = @ticket_id)
ORDER BY sequence_number;
