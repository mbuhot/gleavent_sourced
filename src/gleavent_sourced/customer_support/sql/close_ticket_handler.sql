-- name: TicketClosedEvents :many
with parent_ticket_events as (
    select
        sequence_number,
        event_type,
        payload::text as payload,
        metadata::text as metadata
    from events e
    where e.event_type in ('TicketOpened', 'TicketClosed', 'TicketAssigned') AND
          e.payload @> jsonb_build_object('ticket_id', @ticket_id::text)
),
child_ticket_ids as (
    select distinct e.payload->>'ticket_id' as child_ticket_id
    from events e
    join parent_ticket_events pt on e.payload @> jsonb_build_object('parent_ticket_id', pt.payload::jsonb->>'ticket_id')
    where e.event_type = 'TicketParentLinked'
),
child_ticket_events as (
    select
        e.sequence_number,
        e.event_type,
        e.payload::text as payload,
        e.metadata::text as metadata
    from events e
    join child_ticket_ids ct on (e.payload @> jsonb_build_object('ticket_id', ct.child_ticket_id))
    where e.event_type in ('TicketOpened', 'TicketClosed', 'TicketParentLinked')
),
all_events as (
    select sequence_number, event_type, payload, metadata
    from parent_ticket_events
    union all
    select sequence_number, event_type, payload, metadata
    from child_ticket_events
)
select
    ae.sequence_number,
    ae.event_type,
    ae.payload,
    ae.metadata
from all_events ae
order by ae.sequence_number;
