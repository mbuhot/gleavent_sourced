import gleam/dict
import gleam/list
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/facts
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit_verbose(
    ["gleavent_sourced/parent_child_tickets_test"],
    verbose: True,
  )
}

pub fn create_test_metadata() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}

pub fn child_tickets_fact_test() {
  test_runner.txn(fn(db) {
    // Setup: Create parent ticket and two child tickets
    let parent_opened =
      ticket_events.TicketOpened(
        ticket_id: "PARENT-100",
        title: "Parent ticket",
        description: "This is the parent ticket",
        priority: "high",
      )

    let child1_opened =
      ticket_events.TicketOpened(
        ticket_id: "CHILD-001",
        title: "Child ticket 1",
        description: "First child ticket",
        priority: "medium",
      )

    let child2_opened =
      ticket_events.TicketOpened(
        ticket_id: "CHILD-002",
        title: "Child ticket 2",
        description: "Second child ticket",
        priority: "low",
      )

    // Link child tickets to parent
    let child1_linked =
      ticket_events.TicketParentLinked(
        ticket_id: "CHILD-001",
        parent_ticket_id: "PARENT-100",
      )

    let child2_linked =
      ticket_events.TicketParentLinked(
        ticket_id: "CHILD-002",
        parent_ticket_id: "PARENT-100",
      )

    let initial_events = [
      parent_opened,
      child1_opened,
      child2_opened,
      child1_linked,
      child2_linked,
    ]

    let test_metadata = create_test_metadata()

    // Store initial events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        initial_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Test: Query for child tickets of parent
    let children_fact =
      ticket_facts.child_tickets("PARENT-100", fn(_ctx, children) { children })

    let assert Ok(children) =
      facts.query_event_log(db, [children_fact], [], ticket_events.decode)

    // Verify: Both child tickets are linked
    assert list.length(children) == 2
    assert list.contains(children, "CHILD-001")
    assert list.contains(children, "CHILD-002")
  })
}

pub fn child_tickets_includes_closed_children_test() {
  test_runner.txn(fn(db) {
    // Setup: Create parent and child tickets with linking, then close one child
    let events = [
      ticket_events.TicketOpened(
        ticket_id: "PARENT-200",
        title: "Parent ticket",
        description: "Parent with children",
        priority: "high",
      ),
      ticket_events.TicketOpened(
        ticket_id: "CHILD-003",
        title: "Child ticket 3",
        description: "Child that will be closed",
        priority: "medium",
      ),
      ticket_events.TicketOpened(
        ticket_id: "CHILD-004",
        title: "Child ticket 4",
        description: "Child that stays open",
        priority: "low",
      ),
      ticket_events.TicketParentLinked(
        ticket_id: "CHILD-003",
        parent_ticket_id: "PARENT-200",
      ),
      ticket_events.TicketParentLinked(
        ticket_id: "CHILD-004",
        parent_ticket_id: "PARENT-200",
      ),
    ]

    let test_metadata = create_test_metadata()

    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Action: Close one child ticket
    let child3_closed =
      ticket_events.TicketClosed(
        ticket_id: "CHILD-003",
        resolution: "Fixed the issue",
        closed_at: "2024-01-01T12:00:00Z",
      )

    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [child3_closed],
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Test: Query for child tickets (should show both children since function returns all linked children)
    let children_fact =
      ticket_facts.child_tickets("PARENT-200", fn(_ctx, children) { children })

    let assert Ok(children) =
      facts.query_event_log(db, [children_fact], [], ticket_events.decode)

    // Verify: Both children are returned (function no longer filters closed tickets for performance)
    assert list.length(children) == 2
    assert list.contains(children, "CHILD-004")
    assert list.contains(children, "CHILD-003")
  })
}

pub fn no_children_for_parent_without_children_test() {
  test_runner.txn(fn(db) {
    // Setup: Create parent ticket with no children
    let parent_only =
      ticket_events.TicketOpened(
        ticket_id: "PARENT-300",
        title: "Childless parent",
        description: "Parent with no children",
        priority: "medium",
      )

    let test_metadata = create_test_metadata()

    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [parent_only],
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Test: Query for child tickets
    let children_fact =
      ticket_facts.child_tickets("PARENT-300", fn(_ctx, children) { children })

    let assert Ok(children) =
      facts.query_event_log(db, [children_fact], [], ticket_events.decode)

    // Verify: No children
    assert children == []
  })
}
