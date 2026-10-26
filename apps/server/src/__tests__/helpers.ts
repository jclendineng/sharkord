import { sha256, UploadHeaders } from '@sharkord/shared';
import { spyOn } from 'bun:test';
import jwt from 'jsonwebtoken';
import type WebSocket from 'ws';
import { getTokenSessionId } from '../helpers/session-token';
import { createSessionToken } from '../helpers/sessions';
import { appRouter } from '../routers';
import * as pushRelay from '../utils/push-relay';
import type { Context } from '../utils/trpc';
import { createMockContext, type TMockContextOptions } from './context';
import { TEST_SECRET_TOKEN } from './seed';
import { testsBaseUrl } from './setup';

const getMockedToken = async (userId: number, tokenVersion: number = 0) => {
  const hashedToken = await sha256(TEST_SECRET_TOKEN);

  const token = jwt.sign({ userId: userId, tokenVersion }, hashedToken, {
    expiresIn: '86400s'
  });

  return token;
};

type TFakeSocket = WebSocket & {
  closes: { code: number; reason?: string }[];
};

const createFakeSocket = () => {
  const closes: TFakeSocket['closes'] = [];

  return {
    closes,
    close: (code: number, reason?: string) => closes.push({ code, reason })
  } as unknown as TFakeSocket;
};

const getCaller = async (
  userId: number,
  connection?: Omit<TMockContextOptions, 'customToken'>,
  ctxOverrides?: Partial<Context>
) => {
  const mockedToken = await getMockedToken(userId);

  const caller = appRouter.createCaller({
    ...(await createMockContext({
      ...connection,
      customToken: mockedToken
    })),
    ...ctxOverrides
  });

  return { caller, mockedToken };
};

// a caller whose token belongs to a session, the way a real login is. getCaller's token
// predates sessions and carries none. passing an earlier caller's token connects that same
// login again, as a device reconnecting does
const getSessionCaller = async (
  userId: number,
  socket?: WebSocket,
  existingToken?: string
) => {
  const token =
    existingToken ?? (await createSessionToken(userId, 0, undefined));
  const caller = appRouter.createCaller(
    await createMockContext({ customToken: token, socket })
  );
  const { handshakeHash } = await caller.others.handshake();

  await caller.others.joinServer({ handshakeHash });

  return { caller, token, sessionId: getTokenSessionId(token)! };
};

// this will basically simulate a specific user connecting to the server
const initTest = async (
  userId: number = 1,
  connection?: Omit<TMockContextOptions, 'customToken'>,
  ctxOverrides?: Partial<Context>
) => {
  const { caller, mockedToken } = await getCaller(
    userId,
    connection,
    ctxOverrides
  );
  const { handshakeHash } = await caller.others.handshake();

  const initialData = await caller.others.joinServer({
    handshakeHash: handshakeHash
  });

  return { caller, mockedToken, initialData };
};

const login = async (
  identity: string,
  password: string,
  invite?: string,
  headers?: Record<string, string>
) =>
  fetch(`${testsBaseUrl}/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...headers
    },
    body: JSON.stringify({
      identity,
      password,
      invite
    })
  });

type TCaller = Awaited<ReturnType<typeof getCaller>>['caller'];
type TSendMessageInput = Parameters<TCaller['messages']['send']>[0];

// a message that is stored always has an id, null is only an ephemeral command
const sendMessage = async (caller: TCaller, input: TSendMessageInput) => {
  const messageId = await caller.messages.send(input);

  if (messageId === null) {
    throw new Error('The message was not stored.');
  }

  return messageId;
};

const uploadFile = async (file: File, token: string) =>
  fetch(`${testsBaseUrl}/upload`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/octet-stream',
      [UploadHeaders.TYPE]: file.type,
      [UploadHeaders.CONTENT_LENGTH]: file.size.toString(),
      [UploadHeaders.ORIGINAL_NAME]: encodeURIComponent(file.name),
      [UploadHeaders.TOKEN]: token
    },
    body: file
  });

// uploads are stored under a random uuid, never their own name, with the extension kept
// what the app makes for each server: a p-256 key pair, the public half sent as x963 base64url.
// one shared by every test device, so a test can open whatever the relay was handed
const createPushKey = async () => {
  const pair = (await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    ['deriveBits']
  )) as CryptoKeyPair;
  const raw = await crypto.subtle.exportKey('raw', pair.publicKey);

  return {
    privateKey: pair.privateKey,
    encryptionKey: Buffer.from(raw).toString('base64url')
  };
};

const testPushKey = await createPushKey();

// the relay's id and ticket for a user's device, so a relay call says who it was for
const pushDeviceId = (userId: number) => `${userId}`.padStart(64, 'c');
const pushTicket = (userId: number) => `ticket-for-${userId}`;

// registers the user's device the way the app does, with a ticket from the relay
const registerPushDevice = async (userId: number) => {
  const { caller } = await initTest(userId);

  await caller.notifications.registerDevice({
    token: pushDeviceId(userId),
    relayTicket: pushTicket(userId),
    encryptionKey: testPushKey.encryptionKey
  });
};

// the relay is not reached from tests, its answer is apple's status and reason
const spyOnPushRelay = (status = 200, reason?: string) =>
  spyOn(pushRelay, 'sendRelayNotification').mockResolvedValue({
    status,
    reason
  });

type TPushRelaySpy = ReturnType<typeof spyOnPushRelay>;

const pushedTickets = (spy: TPushRelaySpy) =>
  spy.mock.calls.map(([notification]) => notification.ticket).sort();

// the app's side of utils/push-encryption, so a test reads what the device would show
const openPush = async (
  encrypted: string,
  privateKey: CryptoKey = testPushKey.privateKey
) => {
  const bytes = Buffer.from(encrypted, 'base64url');
  const ephemeralPublicKey = bytes.subarray(0, 65);
  const ephemeral = await crypto.subtle.importKey(
    'raw',
    ephemeralPublicKey,
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    []
  );
  const sharedSecret = await crypto.subtle.deriveBits(
    { name: 'ECDH', public: ephemeral },
    privateKey,
    256
  );
  const hkdfKey = await crypto.subtle.importKey(
    'raw',
    sharedSecret,
    'HKDF',
    false,
    ['deriveKey']
  );
  const aesKey = await crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: ephemeralPublicKey,
      info: new TextEncoder().encode('sharkord push v1')
    },
    hkdfKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['decrypt']
  );
  const opened = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: bytes.subarray(65, 77) },
    aesKey,
    bytes.subarray(77)
  );

  return JSON.parse(new TextDecoder().decode(opened));
};

// what the device would read from the relay's first push, or the one at index
const pushedPayload = async (spy: TPushRelaySpy, index = 0) => {
  const call = spy.mock.calls[index];

  if (!call) {
    throw new Error(`the relay was not handed push ${index}`);
  }

  const [notification] = call;

  return openPush(notification.encrypted);
};

const storedNamePattern = (extension: string) =>
  new RegExp(
    `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}${extension.replace(/\./g, '\\.')}$`
  );

export {
  createFakeSocket,
  createPushKey,
  getCaller,
  getMockedToken,
  getSessionCaller,
  initTest,
  login,
  openPush,
  pushDeviceId,
  pushedPayload,
  pushedTickets,
  pushTicket,
  registerPushDevice,
  sendMessage,
  spyOnPushRelay,
  storedNamePattern,
  testPushKey,
  uploadFile,
  type TFakeSocket
};
