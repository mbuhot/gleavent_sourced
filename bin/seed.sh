#!/bin/bash

# Script to populate test data and demonstrate GIN index performance
# This creates enough data to show the dramatic performance difference

set -e

echo "=== EventFilter Performance Benchmark ==="
echo "Populating test data and comparing old vs new query performance"
echo ""

# Database connection
DB_URL=${DATABASE_URL:-"postgresql://postgres:postgres@localhost:5432/gleavent_sourced_dev"}

echo "Connecting to: $(echo $DB_URL | sed 's/:\/\/.*@/:\/\/***:***@/')"
echo ""

# Create temporary SQL file
cat > /tmp/seeds.sql << 'EOF'
-- Clean up any existing test data
DELETE FROM events;

\echo 'Inserting 1000,000 test events...'

-- Insert a variety of test data to demonstrate performance
INSERT INTO events (event_type, payload, metadata)
SELECT
  'TicketOpened',
  jsonb_build_object(
    'ticket_id', 'T-' || i,
    'title', 'Performance test ticket ' || i,
    'description', 'Generated for benchmarking',
    'priority', CASE
      WHEN i % 4 = 0 THEN 'critical'
      WHEN i % 4 = 1 THEN 'high'
      WHEN i % 4 = 2 THEN 'medium'
      ELSE 'low'
    END,
    'department', CASE
      WHEN i % 3 = 0 THEN 'engineering'
      WHEN i % 3 = 1 THEN 'sales'
      ELSE 'support'
    END,
    'customer_tier', CASE
      WHEN i % 5 = 0 THEN 'enterprise'
      WHEN i % 5 = 1 THEN 'business'
      ELSE 'basic'
    END
  ),
  jsonb_build_object('source', 'benchmark_test', 'batch', '1')
FROM generate_series(1, 500000) as i;

INSERT INTO events (event_type, payload, metadata)
SELECT
  'TicketAssigned',
  jsonb_build_object(
    'ticket_id', 'T-' || i,
    'assignee', 'user-' || (i % 50),
    'assigned_at', '2024-01-01T10:00:00Z',
    'priority', CASE
      WHEN i % 4 = 0 THEN 'critical'
      WHEN i % 4 = 1 THEN 'high'
      WHEN i % 4 = 2 THEN 'medium'
      ELSE 'low'
    END
  ),
  jsonb_build_object('source', 'benchmark_test', 'batch', '2')
FROM generate_series(1, 300000) as i;

INSERT INTO events (event_type, payload, metadata)
SELECT
  'TicketClosed',
  jsonb_build_object(
    'ticket_id', 'T-' || i,
    'resolution', CASE
      WHEN i % 3 = 0 THEN 'fixed'
      WHEN i % 3 = 1 THEN 'duplicate'
      ELSE 'wont-fix'
    END,
    'closed_at', '2024-01-02T15:30:00Z'
  ),
  jsonb_build_object('source', 'benchmark_test', 'batch', '3')
FROM generate_series(1, 200000) as i;

-- Insert parent-child ticket relationships for join testing
INSERT INTO events (event_type, payload, metadata)
SELECT
  'TicketParentLinked',
  jsonb_build_object(
    'ticket_id', 'T-' || (i * 2),      -- Child ticket ID
    'parent_ticket_id', 'T-' || i      -- Parent ticket ID
  ),
  jsonb_build_object('source', 'benchmark_test', 'batch', '4')
FROM generate_series(1, 50000) as i     -- Creates 500 parent-child relationships
WHERE i * 2 <= 500000;                   -- Ensure child tickets exist

\echo 'Data population complete!'
\echo 'Added parent-child ticket relationships for join testing'
\echo ''
EOF

echo "Runing Seeds..."
echo "================================================"

psql "$DB_URL" -f /tmp/seeds.sql
