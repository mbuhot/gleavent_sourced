-- name: AllChildTicketsClosed :many
with child_ticket_ids as (
    select e.payload->>'ticket_id' as child_ticket_id
    from events e
    where e.event_type = 'TicketParentLinked'
      and e.payload @> jsonb_build_object('parent_ticket_id', @parent_ticket_id::text)
)
select
    e.sequence_number,
    e.event_type,
    e.payload::text as payload,
    e.metadata::text as metadata
from events e
where (
    -- Parent linking events
    (e.event_type = 'TicketParentLinked' and e.payload @> jsonb_build_object('parent_ticket_id', @parent_ticket_id::text))
    or
    -- Child ticket closed events
    (e.event_type = 'TicketClosed' and e.payload->>'ticket_id' in (
        select child_ticket_id from child_ticket_ids
    ))
);

-- name: DuplicateStatus :many
select
    e.sequence_number,
    e.event_type,
    e.payload::text as payload,
    e.metadata::text as metadata
from events e
where e.event_type = 'TicketMarkedDuplicate'
  and (e.payload @> jsonb_build_object('duplicate_ticket_id', @ticket_id::text)
       or e.payload @> jsonb_build_object('original_ticket_id', @ticket_id::text));

-- name: ChildTickets :many
select
    e.sequence_number,
    e.event_type,
    e.payload::text as payload,
    e.metadata::text as metadata
from events e
where e.event_type = 'TicketParentLinked'
  and e.payload @> jsonb_build_object('parent_ticket_id', @parent_ticket_id::text);
