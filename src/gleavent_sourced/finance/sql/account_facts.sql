-- name: DailySpending :many
select
    e.sequence_number,
    e.event_type,
    e.payload as payload,
    e.metadata as metadata
from events e
where (
    (e.event_type = 'MoneyWithdrawn' AND e.payload @> jsonb_build_object('account_id', @account_id::text))
    or
    (e.event_type = 'MoneyTransferred' AND e.payload @> jsonb_build_object('from_account', @account_id::text))
)
and date_trunc('day', to_timestamp((e.payload->>'timestamp')::float)) = date_trunc('day', @today::timestamptz)
order by e.sequence_number;
