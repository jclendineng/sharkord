import type { Database } from 'bun:sqlite';
import { db } from '.';

// drizzle builds a query's sql from scratch on every call. for the few queries nearly every
// request runs (settings, the caller and their roles) that building was most of the server's
// time under load, more than sqlite itself. a prepared statement is built once per connection.
// keyed by the sqlite client rather than `db`, so a test's fresh database gets its own
const statements = new WeakMap<object, Map<string, unknown>>();

const prepared = <TStatement>(
  name: string,
  build: () => TStatement
): TStatement => {
  // drizzle sets $client on every database it makes, the exported type leaves it out
  const { $client: client } = db as typeof db & { $client: Database };
  let byName = statements.get(client);

  if (!byName) {
    byName = new Map();
    statements.set(client, byName);
  }

  let statement = byName.get(name) as TStatement | undefined;

  if (!statement) {
    statement = build();
    byName.set(name, statement);
  }

  return statement;
};

export { prepared };
