import { Database } from 'bun:sqlite';
import { afterAll, describe, expect, test } from 'bun:test';
import { drizzle } from 'drizzle-orm/bun-sqlite';
import { migrate } from 'drizzle-orm/bun-sqlite/migrator';
import fs from 'fs';
import path from 'path';
import {
  BACKUPS_PATH,
  SRC_MIGRATIONS_PATH,
  TMP_PATH
} from '../../helpers/paths';
import { migrateDatabase } from '../migrate';

// an admin moving a server from upstream sharkord to this fork. upstream's migrations after
// the split (0036 to 0044, copied into upstream-migrations/ with their real journal stamps)
// are stamped later than most of ours, so drizzle alone would skip our chain. each case
// builds a genuine upstream database at one of its states and boots this fork on it
const UPSTREAM_FIXTURES = path.join(import.meta.dir, 'upstream-migrations');
const SPLIT_TAG = '0035_grant_send_voice_reaction';

type TJournalEntry = { idx: number; tag: string; when: number };

const workDir = path.join(TMP_PATH, 'upstream-takeover-test');

const forkJournal = JSON.parse(
  fs.readFileSync(
    path.join(SRC_MIGRATIONS_PATH, 'meta', '_journal.json'),
    'utf-8'
  )
) as { entries: TJournalEntry[] };

const upstreamEntries = JSON.parse(
  fs.readFileSync(path.join(UPSTREAM_FIXTURES, 'journal.json'), 'utf-8')
) as { tag: string; when: number }[];

// our 0000 to 0035 are byte for byte upstream's, so the shared part comes from our folder
const buildUpstreamFolder = (lastUpstreamTag: string) => {
  const folder = path.join(workDir, lastUpstreamTag);

  fs.rmSync(folder, { recursive: true, force: true });
  fs.mkdirSync(path.join(folder, 'meta'), { recursive: true });

  const shared = forkJournal.entries.slice(
    0,
    forkJournal.entries.findIndex((entry) => entry.tag === SPLIT_TAG) + 1
  );
  const upstream = upstreamEntries.slice(
    0,
    upstreamEntries.findIndex((entry) => entry.tag === lastUpstreamTag) + 1
  );

  for (const entry of shared) {
    fs.copyFileSync(
      path.join(SRC_MIGRATIONS_PATH, `${entry.tag}.sql`),
      path.join(folder, `${entry.tag}.sql`)
    );
  }

  for (const entry of upstream) {
    fs.copyFileSync(
      path.join(UPSTREAM_FIXTURES, `${entry.tag}.sql`),
      path.join(folder, `${entry.tag}.sql`)
    );
  }

  const entries = [...shared, ...upstream].map((entry, idx) => ({
    idx,
    version: '6',
    when: entry.when,
    tag: entry.tag,
    breakpoints: true
  }));

  fs.writeFileSync(
    path.join(folder, 'meta', '_journal.json'),
    JSON.stringify({ version: '7', dialect: 'sqlite', entries })
  );

  return folder;
};

const hasPluginComponents = (lastUpstreamTag: string) =>
  lastUpstreamTag >= '0037';

const buildUpstreamDatabase = (lastUpstreamTag: string, file = ':memory:') => {
  const sqlite = new Database(file, { create: true, strict: true });

  migrate(drizzle({ client: sqlite }), {
    migrationsFolder: buildUpstreamFolder(lastUpstreamTag)
  });

  // rows a real upstream server would hold. foreign keys off so they need no parents
  sqlite.run('PRAGMA foreign_keys = OFF');
  sqlite.run(
    'INSERT INTO messages (id, content, channel_id, created_at) VALUES (1, ?, 1, 1)',
    ['<p>hello</p>']
  );
  for (const permission of [
    'SET_PROFILE_IMAGE',
    'VIEW_METRICS',
    'MANAGE_UPDATES'
  ]) {
    sqlite.run(
      'INSERT INTO role_permissions (role_id, permission, created_at) VALUES (1, ?, 1)',
      [permission]
    );
  }

  sqlite.run(
    "INSERT INTO plugin_storage (plugin_id, key, value, updated_at) VALUES ('dice', 'rolls', '42', 1)"
  );

  if (hasPluginComponents(lastUpstreamTag)) {
    sqlite.run('UPDATE messages SET plugin_components = ? WHERE id = 1', [
      '[{"type":"button"}]'
    ]);
  }

  sqlite.run('PRAGMA foreign_keys = ON');

  return sqlite;
};

const columnsByTable = (sqlite: Database) => {
  const tables = (
    sqlite
      .query(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
      )
      .all() as { name: string }[]
  ).map(({ name }) => name);

  return new Map(
    tables.map((table) => [
      table,
      (sqlite.query(`PRAGMA table_info(${table})`).all() as { name: string }[])
        .map(({ name }) => name)
        .sort()
    ])
  );
};

const migrationStamps = (sqlite: Database) =>
  (
    sqlite
      .query('SELECT created_at FROM __drizzle_migrations ORDER BY created_at')
      .all() as { created_at: number }[]
  ).map(({ created_at }) => Number(created_at));

const snapshot = (sqlite: Database) =>
  JSON.stringify({
    schema: [...columnsByTable(sqlite)],
    migrations: sqlite
      .query(
        'SELECT id, hash, created_at FROM __drizzle_migrations ORDER BY id'
      )
      .all(),
    pluginStorage: sqlite
      .query("SELECT name FROM sqlite_master WHERE name = 'plugin_storage'")
      .all()
  });

const buildForkDatabase = async () => {
  const sqlite = new Database(':memory:', { strict: true });

  await migrateDatabase(
    sqlite,
    drizzle({ client: sqlite }),
    SRC_MIGRATIONS_PATH
  );

  return sqlite;
};

const freshForkSchema = async () => {
  const sqlite = await buildForkDatabase();
  const schema = columnsByTable(sqlite);

  sqlite.close();

  return schema;
};

const LAST_UPSTREAM = '0044_settings_signed_urls_include_assets';
// upstream's early 0003_add_avatar_and_banner_limits, rewritten before the split and no longer
// in either journal. an old database can still carry it
const REWRITTEN_EARLY_STAMP = 1772053200000;

afterAll(() => {
  fs.rmSync(workDir, { recursive: true, force: true });
});

describe('taking over an upstream database', () => {
  test.each(upstreamEntries.map(({ tag }) => tag))(
    'should end up with the fork schema and keep the data from upstream at %s',
    async (lastUpstreamTag) => {
      const sqlite = buildUpstreamDatabase(lastUpstreamTag);
      const db = drizzle({ client: sqlite });

      await migrateDatabase(sqlite, db, SRC_MIGRATIONS_PATH);

      // every table and column a fresh fork database has. upstream's own extras stay
      const takenOver = columnsByTable(sqlite);

      for (const [table, columns] of await freshForkSchema()) {
        expect(takenOver.get(table)).toEqual(expect.arrayContaining(columns));
      }

      expect(takenOver.has('__upstream_plugin_storage')).toBe(false);
      expect(takenOver.get('messages')).not.toContain(
        '__upstream_plugin_components'
      );

      // drizzle sees our chain, and only ours, as applied
      expect(migrationStamps(sqlite)).toEqual(
        forkJournal.entries.map(({ when }) => when)
      );

      expect(
        sqlite.query('SELECT content FROM messages WHERE id = 1').get()
      ).toEqual({ content: '<p>hello</p>' });

      expect(
        sqlite
          .query(
            "SELECT value FROM plugin_storage WHERE plugin_id = 'dice' AND key = 'rolls'"
          )
          .get()
      ).toEqual({ value: '42' });

      if (hasPluginComponents(lastUpstreamTag)) {
        expect(
          sqlite
            .query('SELECT plugin_components FROM messages WHERE id = 1')
            .get()
        ).toEqual({ plugin_components: '[{"type":"button"}]' });
      }

      expect(
        sqlite
          .query(
            "SELECT count(*) AS count FROM role_permissions WHERE permission IN ('SET_PROFILE_IMAGE', 'VIEW_METRICS', 'MANAGE_UPDATES')"
          )
          .get()
      ).toEqual({ count: 0 });

      // a second boot finds nothing to do
      const before = snapshot(sqlite);

      await migrateDatabase(sqlite, db, SRC_MIGRATIONS_PATH);

      expect(snapshot(sqlite)).toBe(before);

      sqlite.close();
    }
  );

  test('should back the upstream database up before taking it over', async () => {
    fs.mkdirSync(workDir, { recursive: true });

    const file = path.join(workDir, `backup-${Date.now()}.sqlite`);
    const sqlite = buildUpstreamDatabase(LAST_UPSTREAM, file);

    await migrateDatabase(
      sqlite,
      drizzle({ client: sqlite }),
      SRC_MIGRATIONS_PATH
    );

    sqlite.close();

    const backups = fs
      .readdirSync(BACKUPS_PATH)
      .filter(
        (name) =>
          name.startsWith(path.basename(file)) &&
          name.endsWith('.before-upstream-takeover.sqlite')
      );

    expect(backups).toHaveLength(1);

    // the snapshot is the untouched upstream database, the way back
    const backup = new Database(path.join(BACKUPS_PATH, backups[0]!), {
      readonly: true
    });

    expect(migrationStamps(backup)).toContain(
      upstreamEntries[upstreamEntries.length - 1]!.when
    );
    expect(
      backup
        .query("SELECT value FROM plugin_storage WHERE plugin_id = 'dice'")
        .get()
    ).toEqual({ value: '42' });

    backup.close();

    for (const name of backups) {
      fs.rmSync(path.join(BACKUPS_PATH, name), { force: true });
    }
  });

  test('should still take over an upstream database that carries an early rewritten migration', async () => {
    const sqlite = buildUpstreamDatabase(LAST_UPSTREAM);

    sqlite.run(
      "INSERT INTO __drizzle_migrations (hash, created_at) VALUES ('early', ?)",
      [REWRITTEN_EARLY_STAMP]
    );

    await migrateDatabase(
      sqlite,
      drizzle({ client: sqlite }),
      SRC_MIGRATIONS_PATH
    );

    expect(columnsByTable(sqlite).has('user_blocks')).toBe(true);

    sqlite.close();
  });

  // an image rolled back to an older build finds rows from the newer one. that boots, as it
  // did before there was a takeover
  test('should boot a fork database that has migrations from a newer fork version', async () => {
    const sqlite = await buildForkDatabase();
    const last = forkJournal.entries[forkJournal.entries.length - 1]!;

    sqlite.run(
      "INSERT INTO __drizzle_migrations (hash, created_at) VALUES ('newer fork', ?)",
      [last.when + 1]
    );

    const before = snapshot(sqlite);

    await migrateDatabase(
      sqlite,
      drizzle({ client: sqlite }),
      SRC_MIGRATIONS_PATH
    );

    expect(snapshot(sqlite)).toBe(before);

    sqlite.close();
  });

  test('should refuse a database with migrations from both upstream and the fork and leave it untouched', async () => {
    const sqlite = buildUpstreamDatabase(LAST_UPSTREAM);
    const forkOnly = forkJournal.entries.find(
      (entry) => entry.tag === '0078_user_blocks'
    )!;

    sqlite.run(
      "INSERT INTO __drizzle_migrations (hash, created_at) VALUES ('fork', ?)",
      [forkOnly.when]
    );

    const before = snapshot(sqlite);

    await expect(
      migrateDatabase(sqlite, drizzle({ client: sqlite }), SRC_MIGRATIONS_PATH)
    ).rejects.toThrow('both upstream Sharkord and this fork');

    expect(snapshot(sqlite)).toBe(before);

    sqlite.close();
  });

  // a newer upstream release, or a database from anywhere else, could need anything
  test('should refuse a database with migrations it does not recognise and leave it untouched', async () => {
    const sqlite = buildUpstreamDatabase(
      '0044_settings_signed_urls_include_assets'
    );

    sqlite.run(
      "INSERT INTO __drizzle_migrations (hash, created_at) VALUES ('newer', 1799999999999)"
    );

    const before = snapshot(sqlite);

    await expect(
      migrateDatabase(sqlite, drizzle({ client: sqlite }), SRC_MIGRATIONS_PATH)
    ).rejects.toThrow('from a newer upstream Sharkord');

    expect(snapshot(sqlite)).toBe(before);

    sqlite.close();
  });

  // the old upstream server has to still boot on the file, or there is no way back short
  // of the backup
  test('should put the upstream database back when the fork chain fails', async () => {
    const sqlite = buildUpstreamDatabase(
      '0044_settings_signed_urls_include_assets'
    );
    const folder = path.join(workDir, 'broken-fork');

    fs.rmSync(folder, { recursive: true, force: true });
    fs.cpSync(SRC_MIGRATIONS_PATH, folder, { recursive: true });

    const journalPath = path.join(folder, 'meta', '_journal.json');
    const journal = JSON.parse(fs.readFileSync(journalPath, 'utf-8')) as {
      entries: (TJournalEntry & { version: string; breakpoints: boolean })[];
    };
    const last = journal.entries[journal.entries.length - 1]!;

    journal.entries.push({
      idx: last.idx + 1,
      version: '6',
      when: last.when + 1,
      tag: '9999_broken',
      breakpoints: true
    });
    fs.writeFileSync(journalPath, JSON.stringify(journal));
    fs.writeFileSync(path.join(folder, '9999_broken.sql'), 'THIS IS NOT SQL;');

    const before = snapshot(sqlite);

    await expect(
      migrateDatabase(sqlite, drizzle({ client: sqlite }), folder)
    ).rejects.toThrow();

    expect(snapshot(sqlite)).toBe(before);
    expect(
      sqlite
        .query("SELECT value FROM plugin_storage WHERE plugin_id = 'dice'")
        .get()
    ).toEqual({ value: '42' });

    sqlite.close();
  });
});
