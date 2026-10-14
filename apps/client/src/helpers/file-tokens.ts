import type { TFile } from '@sharkord/shared';
import { useSyncExternalStore } from 'react';

type TFileToken = {
  accessToken: string;
  expiresAt: number;
};

type TFileSigner = (
  fileIds: number[]
) => Promise<(TFileToken & { fileId: number })[]>;

// fetch new links this long before the ones on screen run out
const REFRESH_MARGIN_MS = 5 * 60 * 1000;
// files.sign takes at most this many ids per call
const SIGN_BATCH_SIZE = 200;

// newer links than the files in the store carry, by file id
const freshTokens = new Map<number, TFileToken>();
// every signed file shown so far and when its newest link expires
const knownExpiries = new Map<number, number>();
const listeners = new Set<() => void>();

let version = 0;
let refreshTimer: ReturnType<typeof setTimeout> | undefined;
let isRefreshing = false;
// files.sign, handed in by lib/trpc so this module never loads the client and everything the
// client loads
let signer: TFileSigner | undefined;

const setFileSigner = (nextSigner: TFileSigner) => {
  signer = nextSigner;
};

const notify = () => {
  version += 1;

  listeners.forEach((listener) => listener());
};

const subscribe = (listener: () => void) => {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
};

const getVersion = () => version;

// re-renders once links that were on screen have run out, so they are drawn again with fresh
// ones. only components whose links are used after they first render need it: downloads,
// media that loads late
const useFileTokensVersion = () =>
  useSyncExternalStore(subscribe, getVersion, getVersion);

const scheduleRefresh = () => {
  if (!signer || refreshTimer || isRefreshing || knownExpiries.size === 0) {
    return;
  }

  const earliest = Math.min(...knownExpiries.values());
  const delay = Math.max(0, earliest - REFRESH_MARGIN_MS - Date.now());

  refreshTimer = setTimeout(() => {
    refreshTimer = undefined;

    refresh().catch(() => {
      // no client during a reconnect, the next file drawn schedules it again
    });
  }, delay);
};

const refresh = async () => {
  const threshold = Date.now() + REFRESH_MARGIN_MS;
  const fileIds = [...knownExpiries]
    .filter(([, expiresAt]) => expiresAt <= threshold)
    .map(([fileId]) => fileId);

  if (!signer || fileIds.length === 0) {
    scheduleRefresh();

    return;
  }

  isRefreshing = true;

  let earliestReplaced = Infinity;

  try {
    for (let start = 0; start < fileIds.length; start += SIGN_BATCH_SIZE) {
      const batch = fileIds.slice(start, start + SIGN_BATCH_SIZE);
      const signed = await signer(batch);
      const signedIds = new Set(signed.map(({ fileId }) => fileId));

      for (const { fileId, accessToken, expiresAt } of signed) {
        earliestReplaced = Math.min(
          earliestReplaced,
          knownExpiries.get(fileId) ?? Infinity
        );

        freshTokens.set(fileId, { accessToken, expiresAt });
        knownExpiries.set(fileId, expiresAt);
      }

      // deleted, or no longer visible: stop asking for it
      batch
        .filter((fileId) => !signedIds.has(fileId))
        .forEach((fileId) => knownExpiries.delete(fileId));
    }
  } finally {
    isRefreshing = false;
  }

  // the links on screen stay until they run out, swapping a loaded image's link would only
  // load it again
  if (earliestReplaced !== Infinity) {
    setTimeout(notify, Math.max(0, earliestReplaced - Date.now()) + 1000);
  }

  scheduleRefresh();
};

// the link to use for a signed file: its own while that still works, so nothing on screen loads
// again, then the fresh one fetched for it
const getFileToken = (file: TFile): TFileToken | undefined => {
  if (!file._accessToken) {
    return undefined;
  }

  const own: TFileToken = {
    accessToken: file._accessToken,
    expiresAt: file._accessTokenExpiresAt ?? 0
  };
  const fresh = freshTokens.get(file.id);
  const newest = fresh && fresh.expiresAt > own.expiresAt ? fresh : own;

  if (newest.expiresAt > (knownExpiries.get(file.id) ?? 0)) {
    knownExpiries.set(file.id, newest.expiresAt);
  }

  scheduleRefresh();

  if (own.expiresAt > Date.now()) {
    return own;
  }

  return newest;
};

export { getFileToken, setFileSigner, useFileTokensVersion };
