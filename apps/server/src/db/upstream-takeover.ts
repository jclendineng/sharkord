import type { Database } from 'bun:sqlite';
import { logger } from '../logger';

type TMigrationRow = {
  id: number;
  hash: string;
  created_at: number;
};

type TTakeover = {
  rows: TMigrationRow[];
  movedTable: boolean;
  movedColumn: boolean;
};

// upstream sharkord's migrations after this fork split off at 0035, by the stamp drizzle
// writes into __drizzle_migrations. an upstream database carries some prefix of these, and
// drizzle only runs journal entries stamped later than the newest row, which is later than
// every one of ours from 0040 on, so without a takeover the fork would skip its own chain.
// a newer upstream release adds stamps that are not here, and those are refused rather than
// guessed at: add them only after checking what each one changes against our chain
const UPSTREAM_MIGRATIONS = new Map<number, string>([
  [1791932955854, '0036_plugin_storage'],
  [1792007744877, '0037_plugin_message_components'],
  [1792174265715, '0038_threads_and_dm_close'],
  [1793216525337, '0039_grant_set_profile_image'],
  [1793752183410, '0040_settings_rate_limiters'],
  [1795180868792, '0041_typical_naoko'],
  [1795196843687, '0042_settings_media_proxy_link_previews'],
  [1795545922783, '0043_metrics'],
  [1795548569326, '0044_settings_signed_urls_include_assets']
]);

// 0035_grant_send_voice_reaction, the last migration upstream and this fork share
const SPLIT_STAMP = 1788517601742;

// permissions upstream has and the fork doesn't, which upstream's migrations and role editor
// can grant. the apps send a role's permissions back whole when it is saved and the server
// rejects one it doesn't know, so any of these left on a role would make it impossible to edit
const UPSTREAM_PERMISSIONS = [
  'MANAGE_UPDATES',
  'SET_PROFILE_IMAGE',
  'VIEW_METRICS'
];

// upstream's 0036 and 0037 create exactly what our 0060 creates, so they are moved aside for
// it and copied back after. everything else upstream added has a name we never use and is
// left in place: the fork reads none of it, and dropping it would only lose data.
// a future migration of ours that creates one of upstream's names has to be moved aside here
// too, or it fails on every database taken over from upstream
const UPSTREAM_PLUGIN_STORAGE = '__upstream_plugin_storage';
const UPSTREAM_PLUGIN_COMPONENTS = '__upstream_plugin_components';

const tableExists = (sqlite: Database, table: string) =>
  sqlite
    .query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?")
    .get(table) !== null;

const columnExists = (sqlite: Database, table: string, column: string) =>
  (
    sqlite.query(`PRAGMA table_info(${table})`).all() as { name: string }[]
  ).some((info) => info.name === column);

const readMigrationRows = (sqlite: Database): TMigrationRow[] => {
  if (!tableExists(sqlite, '__drizzle_migrations')) return [];

  return sqlite
    .query('SELECT id, hash, created_at FROM __drizzle_migrations')
    .all() as TMigrationRow[];
};

const refuse = (reason: string) =>
  new Error(
    `This database ${reason}, so this server can't take it over. Nothing was changed. Start it with the server it came from, or update this server and try again.`
  );

// only what came after 0035 says whose database this is. stamps from before it that the
// journal no longer lists are upstream's early rewritten migrations, which an old database
// may still carry and which have never mattered to booting.
// a database with any of our own rows after the split is ours: rows we don't know there are
// a newer fork version's, as on rolling an image back, and boot on as they always have
const findUpstreamRows = (
  sqlite: Database,
  journalStamps: Set<number>
): TMigrationRow[] => {
  const afterSplit = readMigrationRows(sqlite).filter(
    (row) => Number(row.created_at) > SPLIT_STAMP
  );
  const upstream = afterSplit.filter((row) =>
    UPSTREAM_MIGRATIONS.has(Number(row.created_at))
  );
  const ours = afterSplit.filter((row) =>
    journalStamps.has(Number(row.created_at))
  );

  if (ours.length > 0) {
    if (upstream.length > 0) {
      throw refuse('has migrations from both upstream Sharkord and this fork');
    }

    return [];
  }

  if (upstream.length < afterSplit.length) {
    throw refuse(
      `has ${afterSplit.length - upstream.length} migration(s) from a newer upstream Sharkord`
    );
  }

  return upstream;
};

// one transaction, so a failure leaves the upstream database exactly as it was
const prepareUpstreamTakeover = (
  sqlite: Database,
  rows: TMigrationRow[]
): TTakeover => {
  const takeover: TTakeover = { rows, movedTable: false, movedColumn: false };

  logger.info(
    'Taking over a database from upstream Sharkord, which last ran %s',
    rows
      .map((row) => UPSTREAM_MIGRATIONS.get(Number(row.created_at)))
      .join(', ')
  );

  sqlite.transaction(() => {
    if (tableExists(sqlite, 'plugin_storage')) {
      sqlite.run(
        `ALTER TABLE plugin_storage RENAME TO ${UPSTREAM_PLUGIN_STORAGE}`
      );
      takeover.movedTable = true;
    }

    // upstream at exactly 0036 has the table but not yet the column
    if (columnExists(sqlite, 'messages', 'plugin_components')) {
      sqlite.run(
        `ALTER TABLE messages RENAME COLUMN plugin_components TO ${UPSTREAM_PLUGIN_COMPONENTS}`
      );
      takeover.movedColumn = true;
    }

    // by stamp: drizzle declares id as SERIAL, which sqlite does not number, so it is null
    for (const row of rows) {
      sqlite.run('DELETE FROM __drizzle_migrations WHERE created_at = ?', [
        row.created_at
      ]);
    }
  })();

  return takeover;
};

// our chain failed and drizzle rolled it back, so putting these back returns the file to
// what upstream left, and upstream still boots on it
const undoUpstreamTakeover = (sqlite: Database, takeover: TTakeover) => {
  sqlite.transaction(() => {
    if (takeover.movedTable) {
      sqlite.run(
        `ALTER TABLE ${UPSTREAM_PLUGIN_STORAGE} RENAME TO plugin_storage`
      );
    }

    if (takeover.movedColumn) {
      sqlite.run(
        `ALTER TABLE messages RENAME COLUMN ${UPSTREAM_PLUGIN_COMPONENTS} TO plugin_components`
      );
    }

    for (const row of takeover.rows) {
      sqlite.run(
        'INSERT INTO __drizzle_migrations (id, hash, created_at) VALUES (?, ?, ?)',
        [row.id, row.hash, row.created_at]
      );
    }
  })();
};

// runs on every boot, not only the one that took over: if this step failed after our chain
// committed, the next boot has no upstream rows left to notice, and the plugin data would sit
// in the renamed table for good
const finishUpstreamTakeover = (sqlite: Database) => {
  const hasTable = tableExists(sqlite, UPSTREAM_PLUGIN_STORAGE);
  const hasColumn = columnExists(
    sqlite,
    'messages',
    UPSTREAM_PLUGIN_COMPONENTS
  );

  if (!hasTable && !hasColumn) return;

  sqlite.transaction(() => {
    if (hasTable) {
      sqlite.run(
        `INSERT OR REPLACE INTO plugin_storage (plugin_id, key, value, updated_at) SELECT plugin_id, key, value, updated_at FROM ${UPSTREAM_PLUGIN_STORAGE}`
      );
      sqlite.run(`DROP TABLE ${UPSTREAM_PLUGIN_STORAGE}`);
    }

    if (hasColumn) {
      sqlite.run(
        `UPDATE messages SET plugin_components = ${UPSTREAM_PLUGIN_COMPONENTS} WHERE ${UPSTREAM_PLUGIN_COMPONENTS} IS NOT NULL`
      );
      sqlite.run(
        `ALTER TABLE messages DROP COLUMN ${UPSTREAM_PLUGIN_COMPONENTS}`
      );
    }

    sqlite.run(
      `DELETE FROM role_permissions WHERE permission IN (${UPSTREAM_PERMISSIONS.map(() => '?').join(', ')})`,
      UPSTREAM_PERMISSIONS
    );
  })();

  logger.info('Finished taking over the database from upstream Sharkord');
};

export {
  findUpstreamRows,
  finishUpstreamTakeover,
  prepareUpstreamTakeover,
  undoUpstreamTakeover
};
export type { TTakeover };
