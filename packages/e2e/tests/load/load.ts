import { Permission, type TJoinedMessage } from '@sharkord/shared';
import { spawn } from 'bun';
import { Database } from 'bun:sqlite';
import path from 'path';
import { joinCrowdMember, type TCrowdMember } from '../helpers/crowd';
import { e2eDataPath } from '../statics';

// a thousand people on one server at once, without browsers: they join together, all talk in
// one channel, pile reactions onto one message, type, open direct messages, block each other,
// drop and come back. every step checks what each member received and the server's health
// while it ran. run with `bun run test:load`, or LOAD_SIZE=200 for a smaller crowd. it seeds
// and starts its own server, so nothing else may be listening on the server port

const LOAD_SIZE = Number(process.env.LOAD_SIZE ?? 1000);
const JOIN_CONCURRENCY = 50;
const BURST_SPREAD_MS = 5_000;
const STEADY_RATE = 20;
const STEADY_MESSAGES = 200;
const DELIVERY_TIMEOUT_MS = 120_000;
const SERVER_URL = 'http://localhost:4991';
const LIVE_MESSAGES_CHANNEL = 'Live Messages';
// Member, the role a new account gets in the seed
const DEFAULT_ROLE_ID = 2;
const RUN_ID = Date.now().toString().slice(-8);

type TCheck = { name: string; ok: boolean; detail: string };

const checks: TCheck[] = [];

const check = (name: string, ok: boolean, detail = '') => {
  checks.push({ name, ok, detail });
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`
  );
};

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const percentile = (values: number[], p: number) => {
  if (values.length === 0) {
    return 0;
  }

  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(
    sorted.length - 1,
    Math.floor((p / 100) * sorted.length)
  );

  return Math.round(sorted[index]!);
};

// waits until `done` holds or the time runs out, and says which
const waitFor = async (
  done: () => boolean,
  timeoutMs = DELIVERY_TIMEOUT_MS
) => {
  const deadline = performance.now() + timeoutMs;

  while (performance.now() < deadline) {
    if (done()) {
      return true;
    }

    await sleep(250);
  }

  return done();
};

// runs `task` over every item, `limit` at a time
const inBatches = async <T, R>(
  items: T[],
  limit: number,
  task: (item: T) => Promise<R>
) => {
  const results: R[] = new Array(items.length);
  let next = 0;

  const worker = async () => {
    while (next < items.length) {
      const index = next++;

      results[index] = await task(items[index]!);
    }
  };

  await Promise.all(Array.from({ length: limit }, worker));

  return results;
};

// how long the server takes to answer /healthz while the crowd works it, which tracks how
// long its event loop is blocked, and how much memory it holds
const startHealthSampler = (serverPid: number) => {
  const latencies: number[] = [];
  const rssMb: number[] = [];
  // the step each sample was taken in, to say which one held the server up
  const phases: string[] = [];
  let phase = 'start';
  let failures = 0;
  let running = true;

  const loop = async () => {
    while (running) {
      // timed by curl in a process of its own: this one is busy with a thousand clients, and
      // timing it here measured how far behind they were rather than the server
      const curl = Bun.spawn(
        [
          'curl',
          '-s',
          '-o',
          '/dev/null',
          '-m',
          '10',
          '-w',
          '%{http_code} %{time_total}',
          `${SERVER_URL}/healthz`
        ],
        { stdout: 'pipe' }
      );
      const [code, seconds] = (await new Response(curl.stdout).text())
        .trim()
        .split(' ');

      if (code === '200') {
        latencies.push(Number(seconds) * 1000);
        phases.push(phase);
      } else {
        failures++;
      }

      const ps = Bun.spawnSync(['ps', '-o', 'rss=', '-p', String(serverPid)]);
      const rssKb = Number(ps.stdout.toString().trim());

      if (rssKb > 0) {
        rssMb.push(rssKb / 1024);
      }

      await sleep(500);
    }
  };

  const done = loop();

  // the slowest health check in each step, in the order the steps ran
  const slowestByPhase = () => {
    const slowest = new Map<string, number>();

    latencies.forEach((latency, index) => {
      const name = phases[index]!;

      slowest.set(name, Math.max(slowest.get(name) ?? 0, latency));
    });

    return slowest;
  };

  return {
    latencies,
    rssMb,
    slowestByPhase,
    mark: (name: string) => {
      phase = name;
    },
    failures: () => failures,
    stop: async () => {
      running = false;
      await done;
    }
  };
};

// the seeded member role can't react, which every crowd member needs for the reaction storm.
// granted straight in the database the seed just made, before the server opens it
const grantReactions = () => {
  const db = new Database(path.join(e2eDataPath, 'db.sqlite'));

  db.run(
    'insert or ignore into role_permissions (role_id, permission, created_at) values (?, ?, ?)',
    [DEFAULT_ROLE_ID, Permission.REACT_TO_MESSAGES, Date.now()]
  );
  db.close();
};

const startServer = async () => {
  // a server left from an earlier run would answer for this one with a database the seed has
  // since replaced
  const isTaken = await fetch(`${SERVER_URL}/healthz`).then(
    () => true,
    () => false
  );

  if (isTaken) {
    throw new Error(
      `something is already listening on ${SERVER_URL}, stop it first`
    );
  }

  // LOAD_PROFILE_DIR=<dir> writes the server's cpu profile there when it stops
  const profileDir = process.env.LOAD_PROFILE_DIR;
  const profileFlags = profileDir
    ? ['--cpu-prof', `--cpu-prof-dir=${profileDir}`]
    : [];

  const server = spawn(['bun', ...profileFlags, './src/index.ts'], {
    cwd: path.resolve(import.meta.dir, '../../../../apps/server'),
    env: { ...process.env, SHARKORD_DATA_PATH: e2eDataPath },
    stdout: 'ignore',
    stderr: 'ignore'
  });

  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      const response = await fetch(`${SERVER_URL}/healthz`);

      if (response.ok) {
        return server;
      }
    } catch {
      // not listening yet
    }

    await sleep(500);
  }

  server.kill();
  throw new Error('the server did not start');
};

// the first error's message, to say why a step failed
const firstError = (errors: unknown[]) => {
  if (errors.length === 0) {
    return '';
  }

  const [error] = errors;

  return `, first: ${error instanceof Error ? error.message : String(error)}`;
};

const tokenOf = (message: TJoinedMessage) => message.content ?? '';

// every member must hold each expected token exactly once
const deliveryReport = (
  crowd: TCrowdMember[],
  tokens: Set<string>,
  from: number
) => {
  let missing = 0;
  let duplicated = 0;

  for (const member of crowd) {
    const seen = new Map<string, number>();

    for (const message of member.received.slice(from)) {
      const token = tokenOf(message);

      if (tokens.has(token)) {
        seen.set(token, (seen.get(token) ?? 0) + 1);
      }
    }

    missing += tokens.size - seen.size;

    for (const count of seen.values()) {
      if (count > 1) {
        duplicated += count - 1;
      }
    }
  }

  return { missing, duplicated };
};

const run = async () => {
  console.log(`load test: ${LOAD_SIZE} members, run ${RUN_ID}\n`);

  grantReactions();

  const server = await startServer();
  const health = startHealthSampler(server.pid);

  try {
    health.mark('join');

    // 1. everyone joins: signs up, connects, joins the server and starts listening
    const joinStarted = performance.now();
    const indexes = Array.from({ length: LOAD_SIZE }, (_, index) => index);
    const crowd = await inBatches(indexes, JOIN_CONCURRENCY, (index) =>
      joinCrowdMember(index)
    );
    const joinSeconds = (performance.now() - joinStarted) / 1000;

    check(
      `${LOAD_SIZE} members join`,
      new Set(crowd.map(({ userId }) => userId)).size === LOAD_SIZE,
      `${joinSeconds.toFixed(1)}s`
    );

    const channelId = crowd[0]!.channelIdByName(LIVE_MESSAGES_CHANNEL);

    health.mark('burst');

    // 2. everyone sends one message inside a few seconds, and everyone must get all of them
    const burstFrom = crowd.map((member) => member.received.length);
    const sentAt = new Map<string, number>();
    const tokens = new Set<string>();
    const sendErrors: unknown[] = [];

    await Promise.all(
      crowd.map(async (member) => {
        await sleep(Math.random() * BURST_SPREAD_MS);

        const token = `<p>burst ${member.index} ${RUN_ID}</p>`;

        tokens.add(token);
        sentAt.set(token, performance.now());

        try {
          await member.client().messages.send.mutate({
            channelId,
            content: token,
            files: []
          });
        } catch (error) {
          sendErrors.push(error);
        }
      })
    );

    check(
      'every burst message is accepted',
      sendErrors.length === 0,
      `${sendErrors.length} refused${firstError(sendErrors)}`
    );

    const expectedDeliveries = LOAD_SIZE * tokens.size;

    await waitFor(() => deliveryReport(crowd, tokens, 0).missing === 0);

    const burst = deliveryReport(crowd, tokens, 0);
    const latencies: number[] = [];

    crowd.forEach((member, memberIndex) => {
      member.received.forEach((message, index) => {
        const sent = sentAt.get(tokenOf(message));

        if (sent !== undefined && index >= burstFrom[memberIndex]!) {
          latencies.push(member.receivedAt[index]! - sent);
        }
      });
    });

    check(
      `all ${expectedDeliveries.toLocaleString()} burst deliveries arrive`,
      burst.missing === 0,
      `${burst.missing} missing`
    );
    check(
      'no member gets a message twice',
      burst.duplicated === 0,
      `${burst.duplicated} duplicates`
    );
    console.log(
      `      delivery time p50 ${percentile(latencies, 50)}ms, p95 ${percentile(latencies, 95)}ms, p99 ${percentile(latencies, 99)}ms`
    );

    // the channel's history holds exactly the burst, in order, once each
    const reader = crowd[0]!;
    let history: TJoinedMessage[] = [];
    let cursor: { createdAt: number; id: number } | null = null;

    do {
      const page = await reader
        .client()
        .messages.get.query({ channelId, cursor, limit: 100 });

      history = history.concat(page.messages);
      cursor = page.nextCursor;
    } while (
      cursor &&
      history.filter((message) => tokens.has(tokenOf(message))).length <
        tokens.size
    );

    const stored = history.filter((message) => tokens.has(tokenOf(message)));
    const storedIds = stored.map(({ id }) => id);
    const isNewestFirst = storedIds.every(
      (id, index) => index === 0 || id < storedIds[index - 1]!
    );

    check(
      'history holds every burst message once, in order',
      stored.length === tokens.size &&
        new Set(storedIds).size === stored.length &&
        isNewestFirst,
      `${stored.length} of ${tokens.size}`
    );

    health.mark('steady');

    // 2b. a busy channel rather than a stampede: twenty messages a second for ten seconds from
    // random members, the pace a lively thousand person server might see
    const steadyFrom = crowd.map((member) => member.received.length);
    const steadySentAt = new Map<string, number>();

    for (let tick = 0; tick < STEADY_MESSAGES; tick++) {
      const member = crowd[Math.floor(Math.random() * crowd.length)]!;
      const token = `<p>steady ${tick} ${RUN_ID}</p>`;

      steadySentAt.set(token, performance.now());
      member
        .client()
        .messages.send.mutate({ channelId, content: token, files: [] })
        .catch((error: unknown) => sendErrors.push(error));

      await sleep(1_000 / STEADY_RATE);
    }

    const steadyTokens = new Set(steadySentAt.keys());

    await waitFor(() => deliveryReport(crowd, steadyTokens, 0).missing === 0);

    const steady = deliveryReport(crowd, steadyTokens, 0);
    const steadyLatencies: number[] = [];

    crowd.forEach((member, memberIndex) => {
      member.received.forEach((message, index) => {
        const sent = steadySentAt.get(tokenOf(message));

        if (sent !== undefined && index >= steadyFrom[memberIndex]!) {
          steadyLatencies.push(member.receivedAt[index]! - sent);
        }
      });
    });

    check(
      `a steady ${STEADY_RATE} messages a second reaches everyone`,
      steady.missing === 0 && steady.duplicated === 0,
      `${steady.missing} missing, ${steady.duplicated} duplicates`
    );
    check(
      'steady traffic arrives within a second',
      percentile(steadyLatencies, 95) < 1_000,
      `p50 ${percentile(steadyLatencies, 50)}ms, p95 ${percentile(steadyLatencies, 95)}ms, p99 ${percentile(steadyLatencies, 99)}ms`
    );

    health.mark('reactions');

    // 3. everyone reacts to the same message at once, and the count comes out exact
    const target = stored[0]!;
    const reactionErrors: unknown[] = [];

    await Promise.all(
      crowd.map(async (member) => {
        await sleep(Math.random() * 2_000);

        try {
          await member.client().messages.toggleReaction.mutate({
            messageId: target.id,
            emoji: 'thumbsup'
          });
        } catch (error) {
          reactionErrors.push(error);
        }
      })
    );

    const reacted = await reader.client().messages.get.query({
      channelId,
      cursor: null,
      limit: 50,
      targetMessageId: target.id
    });
    const reactedMessage = reacted.messages.find(({ id }) => id === target.id);
    const thumbs =
      reactedMessage?.reactions.filter(({ emoji }) => emoji === 'thumbsup')
        .length ?? 0;

    check(
      'every reaction is accepted',
      reactionErrors.length === 0,
      `${reactionErrors.length} refused${firstError(reactionErrors)}`
    );
    check(
      `the message shows ${LOAD_SIZE} reactions`,
      thumbs === LOAD_SIZE,
      `${thumbs} counted`
    );

    health.mark('typing');

    // 4. a hundred people type at once, signalling as the apps do, then stop
    const typers = crowd.slice(0, Math.min(100, LOAD_SIZE));
    const stops = typers.map((member) => member.startTyping(channelId));

    await sleep(4_000);
    stops.forEach((stop) => stop());
    check(
      'typing signals go through',
      typers.every(({ failures }) => failures.length === 0)
    );

    health.mark('direct messages');

    // 5. pairs open direct messages and talk, then some block each other
    const pairs = Math.min(100, Math.floor(LOAD_SIZE / 2));
    const dmErrors: unknown[] = [];
    const dmChannels: number[] = [];

    await Promise.all(
      Array.from({ length: pairs }, async (_, pair) => {
        const one = crowd[pair * 2]!;
        const two = crowd[pair * 2 + 1]!;

        try {
          const { channelId: dmChannelId } = await one
            .client()
            .dms.open.mutate({ userId: two.userId });

          dmChannels[pair] = dmChannelId;
          await one.client().messages.send.mutate({
            channelId: dmChannelId,
            content: `<p>dm ${pair} ${RUN_ID}</p>`,
            files: []
          });
          await two.client().messages.send.mutate({
            channelId: dmChannelId,
            content: `<p>dm reply ${pair} ${RUN_ID}</p>`,
            files: []
          });
        } catch (error) {
          dmErrors.push(error);
        }
      })
    );

    check(
      `${pairs} direct message conversations work`,
      dmErrors.length === 0,
      `${dmErrors.length} failed${firstError(dmErrors)}`
    );

    const blockingPairs = Math.floor(pairs / 2);
    const blockErrors: unknown[] = [];
    let refusedAfterBlock = 0;
    let stillOpen = 0;

    await Promise.all(
      Array.from({ length: pairs }, async (_, pair) => {
        const one = crowd[pair * 2]!;
        const two = crowd[pair * 2 + 1]!;
        const dmChannelId = dmChannels[pair]!;

        try {
          if (pair < blockingPairs) {
            await one.client().friends.block.mutate({ userId: two.userId });
          }

          await two.client().messages.send.mutate({
            channelId: dmChannelId,
            content: `<p>after block ${pair} ${RUN_ID}</p>`,
            files: []
          });

          stillOpen++;
        } catch (error) {
          const message =
            error instanceof Error ? error.message : String(error);

          if (
            pair < blockingPairs &&
            message.includes("couldn't be delivered")
          ) {
            refusedAfterBlock++;
          } else {
            blockErrors.push(error);
          }
        }
      })
    );

    check(
      `${blockingPairs} blocks stop the blocked person's messages`,
      refusedAfterBlock === blockingPairs,
      `${refusedAfterBlock} refused`
    );
    check(
      `${pairs - blockingPairs} conversations without a block still go through`,
      stillOpen === pairs - blockingPairs && blockErrors.length === 0,
      `${stillOpen} sent, ${blockErrors.length} unexpected errors${firstError(blockErrors)}`
    );

    health.mark('reconnect');

    // 6. a fifth of the crowd drops at once and comes back, then a second burst must reach
    // everyone, the returning members included
    const droppers = crowd.slice(0, Math.floor(LOAD_SIZE / 5));

    droppers.forEach((member) => member.disconnect());
    await sleep(1_000);

    const reconnectErrors: unknown[] = [];

    await inBatches(droppers, JOIN_CONCURRENCY, async (member) => {
      try {
        await member.reconnect();
      } catch (error) {
        reconnectErrors.push(error);
      }
    });

    check(
      `${droppers.length} members reconnect at once`,
      reconnectErrors.length === 0,
      `${reconnectErrors.length} failed${firstError(reconnectErrors)}`
    );

    const secondFrom = crowd.map((member) => member.received.length);
    const senders = crowd.slice(-Math.min(200, LOAD_SIZE));
    const secondTokens = new Set(
      senders.map((member) => `<p>second ${member.index} ${RUN_ID}</p>`)
    );

    await Promise.all(
      senders.map(async (member) => {
        await sleep(Math.random() * 2_000);
        await member
          .client()
          .messages.send.mutate({
            channelId,
            content: `<p>second ${member.index} ${RUN_ID}</p>`,
            files: []
          })
          .catch((error: unknown) => sendErrors.push(error));
      })
    );

    const secondMissing = () =>
      crowd.reduce((total, member, memberIndex) => {
        const got = new Set(
          member.received
            .slice(secondFrom[memberIndex])
            .map(tokenOf)
            .filter((token) => secondTokens.has(token))
        );

        return total + (secondTokens.size - got.size);
      }, 0);

    await waitFor(() => secondMissing() === 0);
    check(
      'after the drop every member gets the second burst',
      secondMissing() === 0,
      `${secondMissing()} missing`
    );

    // 7. nothing failed along the way, and the server kept answering
    await health.stop();

    const crowdFailures = crowd.flatMap(({ failures }) => failures);
    const peakRss = Math.max(...health.rssMb);

    check(
      'no member saw an unexpected error',
      crowdFailures.length === 0,
      `${crowdFailures.length} errors${firstError(crowdFailures)}`
    );
    check(
      'the server answered every health check',
      health.failures() === 0,
      `${health.failures()} failed`
    );
    // the stampede of a thousand messages in five seconds is a stress test: it has to finish
    // with every delivery right, and its stall is reported. everything else is what a busy
    // server sees, and has to keep answering inside a second
    const slowest = health.slowestByPhase();
    const everydayPhases = [...slowest].filter(
      ([name]) => name !== 'burst' && name !== 'join'
    );
    const worstEveryday = Math.max(
      0,
      ...everydayPhases.map(([, latency]) => latency)
    );

    check(
      'the server stays responsive through everyday load',
      worstEveryday < 1_000,
      `slowest health check ${Math.round(worstEveryday)}ms outside the stampede, ${Math.round(slowest.get('burst') ?? 0)}ms during it`
    );
    for (const [name, slowest] of health.slowestByPhase()) {
      console.log(
        `      slowest health check during ${name}: ${Math.round(slowest)}ms`
      );
    }

    console.log(
      `      server memory ${Math.round(health.rssMb[0] ?? 0)}MB at start, ${Math.round(peakRss)}MB at peak`
    );

    crowd.forEach((member) => member.disconnect());
  } finally {
    await health.stop();
    server.kill();
    await server.exited;
  }

  const failed = checks.filter(({ ok }) => !ok);

  console.log(
    `\n${checks.length - failed.length} of ${checks.length} checks passed`
  );

  process.exit(failed.length === 0 ? 0 : 1);
};

await run();
