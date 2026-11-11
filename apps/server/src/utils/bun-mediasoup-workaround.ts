/**
 * Bun/Windows mediasoup IPC workaround.
 *
 * On Windows, Bun's `child_process.spawn()` creates broken stdio pipe handles
 * for fd indices >= 3 (oven-sh/bun#11044). The Socket objects look correct
 * (they extend Duplex with .write/.on/.destroy) but the underlying handle has
 * fd=-1 and never connects, so data written to stdio[3] is silently dropped
 * and data never arrives from stdio[4].
 *
 * mediasoup relies on exactly these two extra pipes (fd 3 = producer channel,
 * fd 4 = consumer channel) to send FlatBuffers IPC to its C++ worker process.
 *
 * Fix: monkey-patch `child_process.spawn` *just* for the mediasoup-worker
 * spawn call.  We replace it with `Bun.spawn()`, which correctly returns raw
 * fd numbers for extra stdio handles, then wrap the Bun subprocess in a
 * ChildProcess-compatible EventEmitter with socket-like objects backed by
 * `Bun.connect({fd})`.
 */

import type { SpawnOptions } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { Readable } from 'node:stream';
import { logger } from '../logger.js';

const isBun = typeof globalThis.Bun !== 'undefined';
const isWindows = process.platform === 'win32';

// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
let originalSpawn: Function | null = null;
let patched = false;

// ---------------------------------------------------------------------------
// Bun pipe → Socket-like wrapper
// ---------------------------------------------------------------------------

/**
 * Creates a socket-like EventEmitter backed by `Bun.connect({fd})`.
 *
 * For the **consumer** (read) side this emits `'data'` events with Buffers.
 * For the **producer** (write) side this provides a `.write()` method.
 * Both emit `'end'` / `'error'` and support `.destroy()` /
 * `.removeAllListeners()`, the full surface area mediasoup's Channel needs.
 */
// the socket bun hands back for a pipe, as much of it as is used here
type TBunPipeSocket = {
  write: (chunk: Buffer | Uint8Array) => number;
  flush: () => void;
  end: () => void;
};

// Bun.connect with the undocumented fd option, which its types leave out
type TBunFdConnect = (options: {
  fd: number;
  socket: {
    open: (socket: TBunPipeSocket) => void;
    data: (socket: TBunPipeSocket, data: Uint8Array) => void;
    close: () => void;
    error: (socket: TBunPipeSocket, err: Error) => void;
    drain: () => void;
  };
}) => Promise<unknown>;

// a bun subprocess spawned with five pipes, the last two arriving as raw fd numbers
type TBunWorkerProcess = {
  pid: number;
  stdout: ReadableStream<Uint8Array> | null;
  stderr: ReadableStream<Uint8Array> | null;
  stdio: unknown[];
  kill: (signal?: string) => void;
  exited: Promise<number>;
};

type TPipeSocket = EventEmitter & {
  write: (chunk: Buffer | Uint8Array, encoding?: string) => boolean;
  destroy: () => void;
  readable: boolean;
  writable: boolean;
  readableFlowing: boolean | null;
};

function createBunPipeSocket(fd: number, mode: 'read' | 'write'): TPipeSocket {
  const emitter = new EventEmitter() as EventEmitter & {
    write: (chunk: Buffer | Uint8Array, encoding?: string) => boolean;
    destroy: () => void;
    readable: boolean;
    writable: boolean;
    readableFlowing: boolean | null;
  };

  let bunSocket: TBunPipeSocket | null = null;
  let destroyed = false;

  emitter.readable = mode === 'read';
  emitter.writable = mode === 'write';
  emitter.readableFlowing = null;

  emitter.write = (
    chunk: Buffer | Uint8Array,
    _encoding?: string,
    callback?: (error?: Error | null) => void
  ): boolean => {
    if (destroyed) {
      callback?.(new Error('Socket is destroyed'));
      return false;
    }
    if (!bunSocket) {
      // In practice this never happens: Bun.connect resolves before the
      // first IPC write (which waits for the async WORKER_RUNNING event).
      logger.warn('[bun-mediasoup-fix] write() called before Bun socket ready');
      callback?.(new Error('Socket not ready'));
      return false;
    }
    try {
      const n = bunSocket.write(chunk);
      bunSocket.flush();
      callback?.(null);
      return n > 0;
    } catch (err: unknown) {
      callback?.(err as Error);
      return false;
    }
  };

  emitter.destroy = () => {
    if (destroyed) return;
    destroyed = true;
    if (bunSocket) {
      try {
        bunSocket.end();
      } catch {
        /* ignore */
      }
    }
  };

  // Connect to the pipe fd asynchronously.  The `open` callback fires
  // almost immediately (same tick in practice).
  // NOTE: `fd` is an undocumented Bun.connect option suggested by Jarred
  // (Bun creator) as a workaround for oven-sh/bun#11044.
  const connectToFd = Bun.connect as unknown as TBunFdConnect;

  connectToFd({
    fd,
    socket: {
      open(socket) {
        bunSocket = socket;
      },
      data(_socket, data) {
        if (mode === 'read' && !destroyed) {
          emitter.emit('data', Buffer.from(data));
        }
      },
      close() {
        if (!destroyed) {
          emitter.emit('end');
        }
      },
      error(_socket, err) {
        if (!destroyed) {
          emitter.emit('error', err);
        }
      },
      drain() {}
    }
  }).catch((err: Error) => {
    if (!destroyed) {
      emitter.emit('error', err);
    }
  });

  return emitter;
}

// ---------------------------------------------------------------------------
// stdout / stderr pump helper
// ---------------------------------------------------------------------------

/**
 * Pumps a Bun ReadableStream into a Node.js Readable.
 */
function pumpBunStreamToReadable(
  bunStream: ReadableStream<Uint8Array> | null,
  readable: Readable
) {
  if (!bunStream) return;
  const reader = bunStream.getReader();
  (async () => {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          readable.push(null);
          break;
        }
        readable.push(Buffer.from(value));
      }
    } catch {
      readable.push(null);
    }
  })();
}

// ---------------------------------------------------------------------------
// ChildProcess wrapper
// ---------------------------------------------------------------------------

/**
 * Wraps a Bun Subprocess into a ChildProcess-compatible EventEmitter that
 * mediasoup's WorkerImpl can use transparently.
 */
function wrapBunSubprocess(bunChild: TBunWorkerProcess): EventEmitter {
  const wrapper = new EventEmitter() as EventEmitter & {
    pid: number;
    stdout: Readable;
    stderr: Readable;
    stdio: Array<Readable | TPipeSocket | null>;
    kill: (signal?: string) => void;
  };

  wrapper.pid = bunChild.pid;

  // stdout / stderr → Node Readable
  const stdoutReadable = new Readable({ read() {} });
  const stderrReadable = new Readable({ read() {} });
  pumpBunStreamToReadable(bunChild.stdout, stdoutReadable);
  pumpBunStreamToReadable(bunChild.stderr, stderrReadable);
  wrapper.stdout = stdoutReadable;
  wrapper.stderr = stderrReadable;

  // Extra stdio pipes: Bun gives us raw fd numbers
  const producerFd = bunChild.stdio[3];
  const consumerFd = bunChild.stdio[4];

  if (typeof producerFd !== 'number' || typeof consumerFd !== 'number') {
    throw new Error(
      `[bun-mediasoup-fix] Expected fd numbers for stdio[3] and stdio[4], ` +
        `got: ${typeof producerFd}, ${typeof consumerFd}`
    );
  }

  const producerSocket = createBunPipeSocket(producerFd, 'write');
  const consumerSocket = createBunPipeSocket(consumerFd, 'read');

  wrapper.stdio = [
    null, // stdin  (ignored)
    stdoutReadable, // stdout
    stderrReadable, // stderr
    producerSocket, // fd 3, write TO worker
    consumerSocket // fd 4, read FROM worker
  ];

  // kill()
  wrapper.kill = (signal?: string) => {
    try {
      bunChild.kill(signal);
    } catch {
      try {
        bunChild.kill();
      } catch {
        /* ignore */
      }
    }
  };

  // Forward exit/close events
  bunChild.exited
    .then((exitCode: number) => {
      wrapper.emit('exit', exitCode, null);
      setTimeout(() => wrapper.emit('close', exitCode, null), 0);
    })
    .catch((err: Error) => {
      wrapper.emit('error', err);
    });

  return wrapper;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Monkey-patches `child_process.spawn` so that when mediasoup spawns its
 * worker binary, we use `Bun.spawn()` instead, which correctly supports
 * extra stdio pipe handles on Windows.
 *
 * Call this BEFORE `mediasoup.createWorker()`.
 */
export function patchSpawnForMediasoup(): void {
  if (!isBun || !isWindows || patched) return;

  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const cp = require('node:child_process');
  originalSpawn = cp.spawn;

  cp.spawn = function patchedSpawn(
    command: string,
    args?: string[],
    options?: SpawnOptions
  ) {
    // Only intercept mediasoup-worker spawns (5-element stdio array)
    const isMediasoupWorker =
      typeof command === 'string' &&
      command.includes('mediasoup-worker') &&
      Array.isArray(options?.stdio) &&
      options.stdio.length >= 5;

    if (!isMediasoupWorker) {
      return originalSpawn!.call(cp, command, args, options);
    }

    logger.debug(
      '[bun-mediasoup-workaround] Intercepting spawn of mediasoup-worker with Bun.spawn()'
    );

    const bunSpawnOptions: Record<string, unknown> = {
      stdio: ['ignore', 'pipe', 'pipe', 'pipe', 'pipe'],
      env: options?.env || process.env
    };
    // Forward additional spawn options that Bun supports, when provided.
    if (options?.cwd) {
      bunSpawnOptions.cwd = options.cwd;
    }
    if (typeof options?.detached === 'boolean') {
      bunSpawnOptions.detached = options.detached;
    }
    if (typeof options?.uid === 'number') {
      bunSpawnOptions.uid = options.uid;
    }
    if (typeof options?.gid === 'number') {
      bunSpawnOptions.gid = options.gid;
    }
    // five pipes, two past what bun's types describe, which is the point of this workaround
    const bunChild = Bun.spawn(
      [command, ...(args || [])],
      bunSpawnOptions as Parameters<typeof Bun.spawn>[1]
    );

    return wrapBunSubprocess(bunChild as unknown as TBunWorkerProcess);
  };

  patched = true;
}

/**
 * Restores the original `child_process.spawn`.
 * Call this AFTER `mediasoup.createWorker()` resolves.
 */
export function restoreSpawn(): void {
  if (!patched || !originalSpawn) return;

  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const cp = require('node:child_process');
  cp.spawn = originalSpawn;
  originalSpawn = null;
  patched = false;
}
