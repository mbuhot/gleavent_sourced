import gleam/dict

import gleam/option.{None, Some}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts_v2

import gleavent_sourced/facts_v2
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/ticket_facts_v2_test"])
}

pub type TicketContext {
  TicketContext(
    exists: Bool,
    closed: Bool,
    assignee: option.Option(String),
    priority: option.Option(String),
    children: List(String),
    all_children_closed: Bool,
    duplicate_status: ticket_facts_v2.DuplicateStatus,
  )
}

pub fn create_test_metadata() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "ticket_facts_v2_test"),
    #("version", "1"),
  ])
}

pub fn ticket_lifecycle_facts_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    // Create a complete ticket lifecycle
    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Bug report",
        description: "System crashes on startup",
        priority: "high",
      ),
      ticket_events.TicketAssigned(
        ticket_id: "T-200",
        assignee: "bob@company.com",
        assigned_at: "2024-01-15T10:00:00Z",
      ),
      ticket_events.TicketAssigned(
        ticket_id: "T-200",
        assignee: "alice@company.com",
        assigned_at: "2024-01-15T11:00:00Z",
      ),
      ticket_events.TicketClosed(
        ticket_id: "T-200",
        resolution: "fixed",
        closed_at: "2024-01-15T15:00:00Z",
      ),
    ]

    let assert Ok(facts_v2.AppendSuccess) =
      facts_v2.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        [],
        0,
      )

    // Create facts using helper functions
    let facts = [
      ticket_facts_v2.exists("T-200", fn(ctx: TicketContext, exists) {
        TicketContext(..ctx, exists: exists)
      }),
      ticket_facts_v2.is_closed("T-200", fn(ctx: TicketContext, closed) {
        TicketContext(..ctx, closed: closed)
      }),
      ticket_facts_v2.current_assignee(
        "T-200",
        fn(ctx: TicketContext, assignee) {
          TicketContext(..ctx, assignee: assignee)
        },
      ),
      ticket_facts_v2.priority("T-200", fn(ctx: TicketContext, priority) {
        TicketContext(..ctx, priority: priority)
      }),
    ]

    let initial_context =
      TicketContext(
        exists: False,
        closed: False,
        assignee: None,
        priority: None,
        children: [],
        all_children_closed: False,
        duplicate_status: ticket_facts_v2.Unique,
      )

    let assert Ok(final_context) =
      facts_v2.query_event_log(db, facts, initial_context, ticket_events.decode)

    // Verify all facts extracted correctly
    assert final_context.exists == True
    assert final_context.closed == True
    assert final_context.assignee == Some("alice@company.com")
    // Most recent assignment
    assert final_context.priority == Some("high")
  })
}

pub fn parent_child_ticket_facts_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    let events = [
      // Parent ticket
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Epic: New feature",
        description: "Large feature with subtasks",
        priority: "medium",
      ),
      // Child tickets
      ticket_events.TicketOpened(
        ticket_id: "T-101",
        title: "Subtask 1",
        description: "First part",
        priority: "low",
      ),
      ticket_events.TicketOpened(
        ticket_id: "T-102",
        title: "Subtask 2",
        description: "Second part",
        priority: "low",
      ),
      // Link children to parent
      ticket_events.TicketParentLinked(
        ticket_id: "T-101",
        parent_ticket_id: "T-100",
      ),
      ticket_events.TicketParentLinked(
        ticket_id: "T-102",
        parent_ticket_id: "T-100",
      ),
      // Close one child
      ticket_events.TicketClosed(
        ticket_id: "T-101",
        resolution: "completed",
        closed_at: "2024-01-15T12:00:00Z",
      ),
    ]

    let assert Ok(facts_v2.AppendSuccess) =
      facts_v2.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        [],
        0,
      )

    let facts = [
      ticket_facts_v2.child_tickets("T-100", fn(ctx: TicketContext, children) {
        TicketContext(..ctx, children: children)
      }),
      ticket_facts_v2.all_child_tickets_closed(
        "T-100",
        fn(ctx: TicketContext, all_closed) {
          TicketContext(..ctx, all_children_closed: all_closed)
        },
      ),
    ]

    let initial_context =
      TicketContext(
        exists: False,
        closed: False,
        assignee: None,
        priority: None,
        children: [],
        all_children_closed: False,
        duplicate_status: ticket_facts_v2.Unique,
      )

    let assert Ok(final_context) =
      facts_v2.query_event_log(db, facts, initial_context, ticket_events.decode)

    // Should find both child tickets in sequence number order
    assert final_context.children == ["T-101", "T-102"]
    // Not all children are closed (T-102 is still open)
    assert final_context.all_children_closed == False
  })
}

pub fn duplicate_ticket_facts_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-300",
        title: "Original ticket",
        description: "First report",
        priority: "high",
      ),
      ticket_events.TicketOpened(
        ticket_id: "T-301",
        title: "Duplicate ticket",
        description: "Same issue reported again",
        priority: "medium",
      ),
      ticket_events.TicketMarkedDuplicate(
        duplicate_ticket_id: "T-301",
        original_ticket_id: "T-300",
        marked_at: "2024-01-15T14:00:00Z",
      ),
    ]

    let assert Ok(facts_v2.AppendSuccess) =
      facts_v2.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        [],
        0,
      )

    // Test both the duplicate and original ticket perspectives
    let duplicate_fact =
      ticket_facts_v2.duplicate_status("T-301", fn(ctx: TicketContext, status) {
        TicketContext(..ctx, duplicate_status: status)
      })

    let assert Ok(duplicate_context) =
      facts_v2.query_event_log(
        db,
        [duplicate_fact],
        TicketContext(
          exists: False,
          closed: False,
          assignee: None,
          priority: None,
          children: [],
          all_children_closed: False,
          duplicate_status: ticket_facts_v2.Unique,
        ),
        ticket_events.decode,
      )

    // T-301 should be marked as duplicate of T-300
    assert duplicate_context.duplicate_status
      == ticket_facts_v2.DuplicateOf("T-300")

    let original_fact =
      ticket_facts_v2.duplicate_status("T-300", fn(ctx: TicketContext, status) {
        TicketContext(..ctx, duplicate_status: status)
      })

    let assert Ok(original_context) =
      facts_v2.query_event_log(
        db,
        [original_fact],
        TicketContext(
          exists: False,
          closed: False,
          assignee: None,
          priority: None,
          children: [],
          all_children_closed: False,
          duplicate_status: ticket_facts_v2.Unique,
        ),
        ticket_events.decode,
      )

    // T-300 should be marked as duplicated by T-301
    assert original_context.duplicate_status
      == ticket_facts_v2.DuplicatedBy("T-301")
  })
}

pub fn nonexistent_ticket_facts_test() {
  test_runner.txn(fn(db) {
    // Test facts for a ticket that doesn't exist

    let facts = [
      ticket_facts_v2.exists("T-999", fn(ctx: TicketContext, exists) {
        TicketContext(..ctx, exists: exists)
      }),
      ticket_facts_v2.is_closed("T-999", fn(ctx: TicketContext, closed) {
        TicketContext(..ctx, closed: closed)
      }),
      ticket_facts_v2.current_assignee(
        "T-999",
        fn(ctx: TicketContext, assignee) {
          TicketContext(..ctx, assignee: assignee)
        },
      ),
      ticket_facts_v2.priority("T-999", fn(ctx: TicketContext, priority) {
        TicketContext(..ctx, priority: priority)
      }),
    ]

    let initial_context =
      TicketContext(
        exists: False,
        closed: False,
        assignee: None,
        priority: None,
        children: [],
        all_children_closed: False,
        duplicate_status: ticket_facts_v2.Unique,
      )

    let assert Ok(final_context) =
      facts_v2.query_event_log(db, facts, initial_context, ticket_events.decode)

    // All facts should return their default/empty values
    assert final_context.exists == False
    assert final_context.closed == False
    assert final_context.assignee == None
    assert final_context.priority == None
  })
}
