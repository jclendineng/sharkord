import { getErrorMessage } from '@sharkord/shared';
import fs from 'fs/promises';
import { parse, stringify } from 'ini';
import { isIP } from 'net';
import z from 'zod';
import { applyEnvOverrides } from './helpers/apply-env-overrides';
import { ensureServerDirs } from './helpers/ensure-server-dirs';
import { getPrivateIp, getPublicIp } from './helpers/network';
import { CONFIG_INI_PATH } from './helpers/paths';
import { raiseRateLimitDefaults } from './helpers/raise-rate-limit-defaults';
import { deepMerge } from './utils/deep-merge';
import { IS_DEVELOPMENT, IS_TEST } from './utils/env';

const deepFreeze = <T>(value: T): T => {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }

  return value;
};

// apps/push-relay as deployed for the published app
const DEFAULT_PUSH_RELAY_URL = 'https://sharkord-push-relay.compmx.workers.dev';

const zRateLimiter = z.object({
  maxRequests: z.coerce.number().int().positive(),
  windowMs: z.coerce.number().int().positive()
});

const zConfig = z.object({
  server: z.object({
    host: z.string().trim(),
    port: z.coerce.number().int().positive(),
    // the path a reverse proxy serves sharkord under, like /sharkord, empty at the root. with no
    // trailing slash, and stripped from every request whether or not the proxy already did
    basePath: z
      .string()
      .trim()
      .regex(
        /^(\/[\w.~-]+)*$/,
        'basePath looks like /sharkord, with no trailing slash'
      ),
    debug: z.coerce.boolean(),
    backupDatabase: z.coerce.boolean(),
    maxRequestBodyBytes: z.coerce.number().int().positive(),
    allowedOrigins: z
      .preprocess(
        (value) => {
          if (Array.isArray(value)) return value;
          if (typeof value === 'string') return value.split(',');

          return [value];
        },
        z.array(z.string().trim().min(1))
      )
      .default(['*']),
    trustedProxies: z
      .preprocess(
        (value) => {
          if (Array.isArray(value)) return value;
          if (typeof value === 'string') return value.split(',');

          return [value];
        },
        z.array(z.string().trim().min(1))
      )
      .default([])
  }),
  oidc: z.object({
    enabled: z.coerce.boolean(),
    issuer: z.string(),
    clientId: z.string(),
    clientSecret: z.string(),
    redirectUri: z.string(),
    disableLocalLogin: z.coerce.boolean()
  }),
  push: z.object({
    // the relay every notification goes through, which holds the app's apns keys. empty is the
    // one the published app uses, a fork with its own app build sets its own
    relayUrl: z
      .string()
      .trim()
      .transform((url) => url || DEFAULT_PUSH_RELAY_URL),
    // whether push is on at all, mirrored with the settings screens by helpers/config-file-sync,
    // which reads it from the file. kept as it is here so a value it does not understand never
    // throws the whole file away
    relayEnabled: z.unknown().optional()
  }),
  // mirrored with the settings screens by helpers/config-file-sync, which owns these keys, so
  // they are kept as they are here rather than given defaults
  registration: z.record(z.string(), z.unknown()).default({}),
  storage: z.record(z.string(), z.unknown()).default({}),
  gifs: z.record(z.string(), z.unknown()).default({}),
  webRtc: z.object({
    port: z.coerce.number().int().positive(),
    // :: listens on ipv6 as well as ipv4 where the host allows it, opt in since a container
    // without ipv6 would fail to bind it and lose voice entirely
    listenIp: z.string().refine((ip) => isIP(ip) !== 0, 'Invalid listen ip'),
    announcedAddress: z.string(),
    maxBitrate: z.coerce.number().int().positive()
  }),
  rateLimiters: z.object({
    sendAndEditMessage: zRateLimiter,
    deleteMessage: zRateLimiter,
    joinVoiceChannel: zRateLimiter,
    moveMembers: zRateLimiter,
    login: zRateLimiter,
    loginIdentity: zRateLimiter,
    joinServer: zRateLimiter,
    upload: zRateLimiter,
    search: zRateLimiter,
    signalTyping: zRateLimiter,
    getMessages: zRateLimiter,
    markAsRead: zRateLimiter,
    toggleMessageReaction: zRateLimiter,
    addEmoji: zRateLimiter,
    openDirectMessage: zRateLimiter,
    handshake: zRateLimiter,
    updatePassword: zRateLimiter,
    revokeSession: zRateLimiter,
    loginLink: zRateLimiter,
    webhook: zRateLimiter,
    adminCreate: zRateLimiter,
    voiceTransport: zRateLimiter,
    voiceStream: zRateLimiter,
    voiceReaction: zRateLimiter,
    soundboardPlay: zRateLimiter,
    useSecretToken: zRateLimiter,
    pluginExecute: zRateLimiter,
    pluginInstall: zRateLimiter,
    pluginManage: zRateLimiter,
    messageAction: zRateLimiter,
    pluginRoute: zRateLimiter,
    oidc: zRateLimiter,
    pushDevice: zRateLimiter
  })
});

type TConfig = z.infer<typeof zConfig>;

const defaultConfig: TConfig = {
  server: {
    host: '',
    port: 4991,
    basePath: '',
    debug: IS_DEVELOPMENT,
    backupDatabase: true,
    maxRequestBodyBytes: 256 * 1024,
    allowedOrigins: ['*'],
    // a proxy on the same host only. trusting the private ranges let any machine on the lan
    // claim any address in x-forwarded-for, which reset its rate limits and dodged ip bans.
    // a proxy on another machine or in another container is added by its address
    trustedProxies: ['127.0.0.1', '::1']
  },
  oidc: {
    enabled: false,
    issuer: '',
    clientId: '',
    clientSecret: '',
    redirectUri: '',
    disableLocalLogin: false
  },
  // relayEnabled is left to config-file-sync, which writes the settings' value into the file
  push: {
    relayUrl: DEFAULT_PUSH_RELAY_URL
  },
  registration: {},
  storage: {},
  gifs: {},
  webRtc: {
    port: 40000,
    listenIp: '0.0.0.0',
    announcedAddress: '',
    maxBitrate: 30_000_000 // 30 Mbps
  },
  rateLimiters: {
    sendAndEditMessage: {
      maxRequests: 60,
      windowMs: 60_000
    },
    // its own budget: clearing out messages one by one used up the one for sending
    deleteMessage: {
      maxRequests: 120,
      windowMs: 60_000
    },
    joinVoiceChannel: {
      maxRequests: 20,
      windowMs: 60_000
    },
    moveMembers: {
      maxRequests: 20,
      windowMs: 60_000
    },
    login: {
      maxRequests: 5,
      windowMs: 60_000
    },
    // per account rather than per address, so spreading attempts over many addresses does not
    // buy more guesses. looser than the address limit, since anyone can spend it for the owner
    loginIdentity: {
      maxRequests: 10,
      windowMs: 60_000
    },
    joinServer: {
      maxRequests: 5,
      windowMs: 60_000
    },
    upload: {
      maxRequests: 60,
      windowMs: 60_000
    },
    search: {
      maxRequests: 30,
      windowMs: 60_000
    },
    signalTyping: {
      maxRequests: 40,
      windowMs: 5_000
    },
    getMessages: {
      maxRequests: 60,
      windowMs: 10_000
    },
    markAsRead: {
      maxRequests: 60,
      windowMs: 10_000
    },
    toggleMessageReaction: {
      maxRequests: 60,
      windowMs: 10_000
    },
    addEmoji: {
      maxRequests: 10,
      windowMs: 60_000
    },
    openDirectMessage: {
      maxRequests: 10,
      windowMs: 60_000
    },
    handshake: {
      maxRequests: 10,
      windowMs: 60_000
    },
    updatePassword: {
      maxRequests: 5,
      windowMs: 60_000
    },
    // signing your own old devices out one by one, nothing to guess at
    revokeSession: {
      maxRequests: 30,
      windowMs: 60_000
    },
    // a new device asks every couple of seconds whether it was approved yet
    loginLink: {
      maxRequests: 60,
      windowMs: 60_000
    },
    webhook: {
      maxRequests: 30,
      windowMs: 60_000
    },
    adminCreate: {
      maxRequests: 60,
      windowMs: 60_000
    },
    voiceTransport: {
      maxRequests: 30,
      windowMs: 60_000
    },
    voiceStream: {
      maxRequests: 200,
      windowMs: 60_000
    },
    voiceReaction: {
      maxRequests: 20,
      windowMs: 30_000
    },
    // a sound plays for everyone in the call, so it is held to fewer than reactions
    soundboardPlay: {
      maxRequests: 10,
      windowMs: 30_000
    },
    useSecretToken: {
      maxRequests: 5,
      windowMs: 60_000
    },
    pluginExecute: {
      maxRequests: 60,
      windowMs: 60_000
    },
    pluginInstall: {
      maxRequests: 10,
      windowMs: 60_000
    },
    // the web app saves a plugin's settings one key per call, so this is roomy
    pluginManage: {
      maxRequests: 120,
      windowMs: 60_000
    },
    // pinning, ending a poll and deleting an attachment, each limited on its own
    messageAction: {
      maxRequests: 120,
      windowMs: 60_000
    },
    pluginRoute: {
      maxRequests: 300,
      windowMs: 60_000
    },
    oidc: {
      maxRequests: 30,
      windowMs: 60_000
    },
    pushDevice: {
      maxRequests: 10,
      windowMs: 60_000
    }
  }
};

let config: TConfig = structuredClone(defaultConfig);

await ensureServerDirs();

const configExists = await fs.exists(CONFIG_INI_PATH);

if (!configExists) {
  // config does not exist, create it with the default config
  await fs.writeFile(CONFIG_INI_PATH, stringify(config));
} else {
  try {
    // config exists, we need to make sure it is up to date with the schema
    // to make this easy, we will read the existing config, merge it with the default config, and write it back to the file
    // this way we don't have to worry about migrating old config files when we add/remove config options
    const existingConfigText = await fs.readFile(CONFIG_INI_PATH, {
      encoding: 'utf-8'
    });

    const existingConfig = raiseRateLimitDefaults(parse(existingConfigText));
    const mergedConfig = deepMerge(config, existingConfig);

    config = zConfig.parse(mergedConfig);

    await fs.writeFile(CONFIG_INI_PATH, stringify(config));
  } catch (error) {
    // something went wrong, just log the error and overwrite the config file with the default config
    console.error(
      `Error reading or parsing config.ini. Overwriting with default config. Error: ${getErrorMessage(error)}`
    );

    await fs.writeFile(CONFIG_INI_PATH, stringify(config));
  }
}

const envOverridesMap: Record<string, string> = {
  'server.host': 'SHARKORD_HOST',
  'server.port': 'SHARKORD_PORT',
  'server.basePath': 'SHARKORD_BASE_PATH',
  'server.debug': 'SHARKORD_DEBUG',
  'server.backupDatabase': 'SHARKORD_BACKUP_DATABASE',
  'server.maxRequestBodyBytes': 'SHARKORD_MAX_REQUEST_BODY_BYTES',
  'server.allowedOrigins': 'SHARKORD_ALLOWED_ORIGINS',
  'server.trustedProxies': 'SHARKORD_TRUSTED_PROXIES',
  'oidc.enabled': 'SHARKORD_OIDC_ENABLED',
  'oidc.issuer': 'SHARKORD_OIDC_ISSUER',
  'oidc.clientId': 'SHARKORD_OIDC_CLIENT_ID',
  'oidc.clientSecret': 'SHARKORD_OIDC_CLIENT_SECRET',
  'oidc.redirectUri': 'SHARKORD_OIDC_REDIRECT_URI',
  'oidc.disableLocalLogin': 'SHARKORD_OIDC_DISABLE_LOCAL_LOGIN',
  'push.relayUrl': 'SHARKORD_PUSH_RELAY_URL',
  'webRtc.port': 'SHARKORD_WEBRTC_PORT',
  'webRtc.listenIp': 'SHARKORD_WEBRTC_LISTEN_IP',
  'webRtc.announcedAddress': 'SHARKORD_WEBRTC_ANNOUNCED_ADDRESS',
  'webRtc.maxBitrate': 'SHARKORD_WEBRTC_MAX_BITRATE'
};

// validated again after the overrides, otherwise an env var could put a value
// in the config that does not match its type at all
config = zConfig.parse(applyEnvOverrides(config, envOverridesMap));
config = IS_TEST ? config : deepFreeze(config);

const SERVER_PRIVATE_IP = await getPrivateIp();

// only used as the mediasoup announced address when the operator has not set
// one, so an explicit announcedAddress makes the third party lookup pointless
const SERVER_PUBLIC_IP = config.webRtc.announcedAddress
  ? undefined
  : await getPublicIp();

export {
  config,
  deepFreeze,
  defaultConfig,
  envOverridesMap,
  SERVER_PRIVATE_IP,
  SERVER_PUBLIC_IP,
  zConfig
};
