import { watch } from 'fs';
import fs from 'fs/promises';
import { parse, stringify } from 'ini';
import path from 'path';
import { updateSettings } from '../db/mutations/server';
import { publishSettings } from '../db/publishers';
import { getSettings } from '../db/queries/server';
import { logger } from '../logger';
import { CONFIG_INI_PATH, DATA_PATH } from './paths';

// the settings that live in config.ini and in the settings screens alike. a change on either side
// reaches the other: saving the screens writes the file, and an edit to the file, at startup or
// while running, is applied to the database and pushed to everyone connected
type TMirroredValues = {
  allowNewUsers: boolean;
  klipyApiKey: string;
  previewPrivateNetwork: boolean;
};

type TFileValues = Partial<TMirroredValues> & {
  // from the version that only locked these, read once and then dropped from the file
  inviteOnly?: boolean;
};

const MIRRORED_KEYS = [
  'allowNewUsers',
  'klipyApiKey',
  'previewPrivateNetwork'
] as const;

// what was last written to the file, so a value that differs from it is known to be an edit
const LAST_SYNC_PATH = path.join(DATA_PATH, 'config-sync.json');

const WATCH_DEBOUNCE_MS = 300;

const toBoolean = (value: unknown): boolean | undefined => {
  if (value === true || value === 'true') {
    return true;
  }

  if (value === false || value === 'false') {
    return false;
  }

  return undefined;
};

const toSection = (value: unknown): Record<string, unknown> => {
  if (value && typeof value === 'object') {
    return value as Record<string, unknown>;
  }

  return {};
};

const readFileText = async () => {
  try {
    return await fs.readFile(CONFIG_INI_PATH, { encoding: 'utf-8' });
  } catch {
    return '';
  }
};

const readFileValues = async (): Promise<TFileValues> => {
  const parsed = parse(await readFileText());
  const registration = toSection(parsed.registration);
  const gifs = toSection(parsed.gifs);
  const links = toSection(parsed.links);
  const klipyApiKey = gifs.klipyApiKey;

  return {
    allowNewUsers: toBoolean(registration.allowNewUsers),
    klipyApiKey:
      typeof klipyApiKey === 'string' ? klipyApiKey.trim() : undefined,
    previewPrivateNetwork: toBoolean(links.previewPrivateNetwork),
    inviteOnly: toBoolean(registration.inviteOnly)
  };
};

const readDatabaseValues = async (): Promise<TMirroredValues> => {
  const settings = await getSettings();

  return {
    allowNewUsers: settings.allowNewUsers,
    klipyApiKey: settings.klipyApiKey ?? '',
    previewPrivateNetwork: settings.linkPreviewsPrivateNetwork
  };
};

const readLastSync = async (): Promise<TMirroredValues | undefined> => {
  try {
    return JSON.parse(await fs.readFile(LAST_SYNC_PATH, { encoding: 'utf-8' }));
  } catch {
    return undefined;
  }
};

const applyToDatabase = async (changes: Partial<TMirroredValues>) => {
  await updateSettings({
    allowNewUsers: changes.allowNewUsers,
    klipyApiKey:
      changes.klipyApiKey === undefined
        ? undefined
        : changes.klipyApiKey || null,
    linkPreviewsPrivateNetwork: changes.previewPrivateNetwork
  });
};

// rewrites only the mirrored keys, everything else in the file stays as it is
const writeFile = async (values: TMirroredValues) => {
  const parsed = parse(await readFileText());
  const registration = toSection(parsed.registration);
  const storage = toSection(parsed.storage);
  const gifs = toSection(parsed.gifs);
  const links = toSection(parsed.links);

  delete registration.inviteOnly;
  // file links are always signed now, there is nothing left to switch
  delete storage.forceSignedUrls;
  delete storage.signedUrls;

  parsed.registration = {
    ...registration,
    allowNewUsers: values.allowNewUsers
  };
  if (Object.keys(storage).length > 0) {
    parsed.storage = storage;
  } else {
    delete parsed.storage;
  }
  parsed.gifs = { ...gifs, klipyApiKey: values.klipyApiKey };
  parsed.links = {
    ...links,
    previewPrivateNetwork: values.previewPrivateNetwork
  };

  // recorded first, so the watcher sees the write as already in sync
  await fs.writeFile(LAST_SYNC_PATH, JSON.stringify(values));
  await fs.writeFile(CONFIG_INI_PATH, stringify(parsed));
};

// the values in the file that are edits: different from what was last written, or with no
// record yet, set at all. an empty klipy key with no record is the old default, not an edit
const getFileEdits = (
  file: TFileValues,
  last: TMirroredValues | undefined
): Partial<TMirroredValues> => {
  const edits: Partial<TMirroredValues> = {};

  for (const key of MIRRORED_KEYS) {
    const value = file[key];

    if (value === undefined || (last && last[key] === value)) {
      continue;
    }

    if (!last && key === 'klipyApiKey' && value === '') {
      continue;
    }

    Object.assign(edits, { [key]: value });
  }

  if (!last && file.inviteOnly === true) {
    edits.allowNewUsers = false;
  }

  return edits;
};

// at startup, before anyone connects: edits made to the file while the server was down win,
// then the file is brought in line with the database
const syncConfigFile = async () => {
  const [file, last] = await Promise.all([readFileValues(), readLastSync()]);
  const edits = getFileEdits(file, last);

  if (Object.keys(edits).length > 0) {
    await applyToDatabase(edits);

    logger.info(
      'Applied config.ini changes to the server settings: %s',
      Object.keys(edits).join(', ')
    );
  }

  await writeFile(await readDatabaseValues());
};

// after the settings screens saved, so the file shows what they changed
const writeSettingsToConfigFile = async () => {
  await writeFile(await readDatabaseValues());
};

const applyConfigFileEdits = async () => {
  const [file, last] = await Promise.all([readFileValues(), readLastSync()]);
  const edits = getFileEdits(file, last);

  if (Object.keys(edits).length === 0) {
    return;
  }

  await applyToDatabase(edits);
  await writeFile(await readDatabaseValues());
  await publishSettings();

  logger.info(
    'Applied config.ini changes to the server settings: %s',
    Object.keys(edits).join(', ')
  );
};

// the folder is watched rather than the file, editors often save by replacing the file
const watchConfigFile = () => {
  let timer: ReturnType<typeof setTimeout> | undefined;

  watch(DATA_PATH, (_event, fileName) => {
    if (fileName !== path.basename(CONFIG_INI_PATH)) {
      return;
    }

    clearTimeout(timer);

    timer = setTimeout(() => {
      applyConfigFileEdits().catch((error) =>
        logger.error('Could not apply config.ini changes: %o', error)
      );
    }, WATCH_DEBOUNCE_MS);
  });
};

export {
  applyConfigFileEdits,
  syncConfigFile,
  watchConfigFile,
  writeSettingsToConfigFile
};
