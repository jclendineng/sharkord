import type { Browser, BrowserContext, Page } from '@playwright/test';
import { TestId, TYPING_MS, type TJoinedMessage } from '@sharkord/shared';
import { expect, loginAs, test } from './fixtures';
import { LIVE_MESSAGES_CHANNEL, openChannel } from './helpers/channels';
import { crowdName, joinCrowdMember, type TCrowdMember } from './helpers/crowd';
import { messageByText, sendMessage } from './helpers/messages';
import {
  LINK_PROFILES,
  shapeLink,
  type TLink,
  type TLinkProfile
} from './helpers/network';
import { messagesContainer } from './helpers/scroll';

// run this with bun test:crowd, or CROWD_SIZE=200 bun test:crowd for a bigger room. it fills the
// server with that many extra online members, which
// would push the seeded users other specs click on out of the member list, so it runs on its
// own against a freshly seeded server rather than alongside the rest of the suite

const CROWD_SIZE = Number(process.env.CROWD_SIZE ?? 100);
const MESSAGES_PER_MEMBER = 3;
const BURST_SPREAD_MS = 1_500;

// the list stops at a hundred rows and summarizes the rest (MAX_USERS_TO_SHOW)
const MEMBER_LIST_CAP = 100;
const SEEDED_USERS = 5;

// a typer leaves the indicator TYPING_MS + 500 after its last signal (addTypingUser), plus
// however long the congested link takes to deliver the frames queued in front of it
const TYPING_GONE_MS = TYPING_MS + 500 + 5_000;

const RUN_ID = Date.now().toString().slice(-8);

const BURST_TOKEN = new RegExp(`b\\d{3}x\\d-${RUN_ID}`, 'g');

type TObserverSpec = {
  label: string;
  identity: string;
  profile?: TLinkProfile;
};

type TObserver = {
  label: string;
  context: BrowserContext;
  page: Page;
  link?: TLink;
};

// three people watching the room in a real browser, each on a different connection
const OBSERVER_SPECS: TObserverSpec[] = [
  { label: 'desk', identity: 'testowner' },
  { label: 'mobile', identity: 'usera', profile: LINK_PROFILES.mobile },
  { label: 'congested', identity: 'userb', profile: LINK_PROFILES.congested }
];

const burstToken = (member: TCrowdMember, round: number) =>
  `b${String(member.index).padStart(3, '0')}x${round}-${RUN_ID}`;

const typingIndicator = (page: Page) =>
  page.getByTestId(TestId.TYPING_INDICATOR);

const openObserver = async (
  browser: Browser,
  { label, identity, profile }: TObserverSpec
): Promise<TObserver> => {
  const context = await browser.newContext();
  let link: TLink | undefined;

  // before the page exists, so the very first socket is already on the shaped link
  if (profile) {
    link = await shapeLink(context, profile);
  }

  const page = await context.newPage();

  await loginAs(page, identity, 'password123');
  await openChannel(page, LIVE_MESSAGES_CHANNEL);

  return { label, context, page, link };
};

const expectOnEveryObserver = (
  observers: TObserver[],
  check: (page: Page) => Promise<void>
) => Promise.all(observers.map(({ page }) => check(page)));

const expectTypingText = (
  observers: TObserver[],
  text: string | RegExp,
  timeout = 15_000
) =>
  expectOnEveryObserver(observers, (page) =>
    expect(typingIndicator(page)).toHaveText(text, { timeout })
  );

const expectNobodyTyping = (observers: TObserver[]) =>
  expectOnEveryObserver(observers, (page) =>
    expect(typingIndicator(page)).toHaveCount(0, { timeout: TYPING_GONE_MS })
  );

const stopAll = (stops: (() => void)[]) => {
  stops.forEach((stop) => stop());
};

const burstMessagesOf = (member: TCrowdMember, channelId: number) =>
  member.received.filter(
    ({ channelId: messageChannelId, content }) =>
      messageChannelId === channelId && content?.match(BURST_TOKEN)
  );

const burstTokensOnPage = async (page: Page) => {
  const text = await messagesContainer(page).innerText();

  return text.match(BURST_TOKEN) ?? [];
};

const tokenOf = ({ content }: TJoinedMessage) => {
  const match = content?.match(BURST_TOKEN);

  if (!match?.[0]) {
    throw new Error(`not a burst message: ${content}`);
  }

  return match[0];
};

test(`${CROWD_SIZE} people chatting at once on mixed connections`, async ({
  browser
}) => {
  test.skip(!process.env.RUN_CROWD, 'load test, run it with bun test:crowd');
  test.setTimeout(8 * 60_000);

  const observers: TObserver[] = [];
  const crowd: TCrowdMember[] = [];

  try {
    await test.step('the observers sign in on their own links', async () => {
      observers.push(
        ...(await Promise.all(
          OBSERVER_SPECS.map((spec) => openObserver(browser, spec))
        ))
      );
    });

    await test.step(`${CROWD_SIZE} people join at the same moment`, async () => {
      crowd.push(
        ...(await Promise.all(
          Array.from({ length: CROWD_SIZE }, (_, index) =>
            joinCrowdMember(index)
          )
        ))
      );

      expect(new Set(crowd.map(({ userId }) => userId)).size).toBe(CROWD_SIZE);
    });

    const [firstMember] = crowd;

    if (!firstMember) {
      throw new Error('nobody joined');
    }

    const liveChannelId = firstMember.channelIdByName(LIVE_MESSAGES_CHANNEL);
    const generalChannelId = firstMember.channelIdByName('General');

    await test.step('the member list caps at a hundred and counts the rest', async () => {
      const total = CROWD_SIZE + SEEDED_USERS;

      // everyone sorts online first, then by name, so the first hundred crowd members fill
      // the list and everyone after them, the three observers included, is in the summary
      const expectedNames = crowd
        .slice(0, MEMBER_LIST_CAP)
        .map(({ index }) => crowdName(index));

      await expectOnEveryObserver(observers, async (page) => {
        await expect(
          page.getByRole('heading', {
            name: new RegExp(`^Members\\D+${total}$`)
          })
        ).toBeVisible({ timeout: 30_000 });

        await expect
          .poll(
            async () => {
              const rows = await page
                .getByTestId(TestId.MEMBER_ITEM)
                .allTextContents();

              return rows.map((row) => row.match(/Crowd \d{3}/)?.[0] ?? row);
            },
            { timeout: 30_000 }
          )
          .toEqual(expectedNames);

        await expect(
          page.getByText(`+${total - MEMBER_LIST_CAP} more...`)
        ).toBeVisible();
      });
    });

    await test.step('typing in another channel stays in that channel', async () => {
      const stops = crowd
        .slice(0, 20)
        .map((member) => member.startTyping(generalChannelId));

      // a negative, so it is sampled across a window long enough for the slowest link to
      // have delivered anything it was going to
      for (let sample = 0; sample < 6; sample++) {
        await expectOnEveryObserver(observers, (page) =>
          expect(typingIndicator(page)).toHaveCount(0)
        );
        await observers[0]!.page.waitForTimeout(500);
      }

      stopAll(stops);
    });

    await test.step('the indicator names one, then two, then counts the rest', async () => {
      const [first, second, ...rest] = crowd.slice(0, 50);

      if (!first || !second) {
        throw new Error('not enough members');
      }

      const stops = [first.startTyping(liveChannelId)];

      await expectTypingText(observers, `${first.name} is typing...`);

      stops.push(second.startTyping(liveChannelId));

      await expectTypingText(
        observers,
        `${first.name} and ${second.name} are typing...`
      );

      stops.push(...rest.map((member) => member.startTyping(liveChannelId)));

      await expectTypingText(
        observers,
        `${first.name} and 49 others are typing...`
      );

      stopAll(stops);

      await expectNobodyTyping(observers);
    });

    await test.step('sending takes the sender out of the indicator', async () => {
      const [sender, ...others] = crowd.slice(2, 5);

      if (!sender) {
        throw new Error('not enough members');
      }

      const stopSender = sender.startTyping(liveChannelId);
      const otherStops = others.map((member) =>
        member.startTyping(liveChannelId)
      );

      await expectTypingText(
        observers,
        /^Crowd 00[345] and 2 others are typing\.\.\.$/
      );

      stopSender();
      await sender.send(liveChannelId, `typed then sent ${RUN_ID}`);

      await expectOnEveryObserver(observers, (page) =>
        expect(messageByText(page, `typed then sent ${RUN_ID}`)).toHaveCount(
          1,
          {
            timeout: 15_000
          }
        )
      );
      await expectTypingText(
        observers,
        /^Crowd 00[45] and Crowd 00[45] are typing\.\.\.$/
      );

      stopAll(otherStops);

      await expectNobodyTyping(observers);
    });

    await test.step('typers who drop off do not leave a stuck indicator', async () => {
      const droppers = crowd.slice(10, 15);
      const stops = droppers.map((member) => member.startTyping(liveChannelId));

      await expectTypingText(observers, /and 4 others are typing\.\.\.$/);

      // the app closing mid sentence: no last signal, no message, just gone
      stopAll(stops);
      droppers.forEach((member) => member.disconnect());

      await expectNobodyTyping(observers);

      await Promise.all(droppers.map((member) => member.reconnect()));
    });

    const totalBurst = CROWD_SIZE * MESSAGES_PER_MEMBER;

    await test.step(`${CROWD_SIZE * MESSAGES_PER_MEMBER} messages land at once while thirty people type`, async () => {
      const typingStops = crowd
        .slice(50, 80)
        .map((member) => member.startTyping(liveChannelId));

      const congested = observers.find(({ label }) => label === 'congested');

      // a second into the burst, the congested observer loses its connection, with the burst
      // still arriving. it has to reconnect and show the room without gaps or doubles
      const dropMidway = async () => {
        await observers[0]!.page.waitForTimeout(1_000);
        await congested?.link?.cut();
      };

      const sendAll = Promise.all(
        crowd.map(async (member) => {
          for (let round = 0; round < MESSAGES_PER_MEMBER; round++) {
            await new Promise((resolve) =>
              setTimeout(resolve, Math.random() * BURST_SPREAD_MS)
            );
            await member.send(liveChannelId, burstToken(member, round));
          }
        })
      );

      await Promise.all([sendAll, dropMidway()]);

      stopAll(typingStops);
    });

    await test.step('every member received every message exactly once', async () => {
      await expect
        .poll(
          () =>
            crowd.filter(
              (member) =>
                burstMessagesOf(member, liveChannelId).length < totalBurst
            ).length,
          { timeout: 30_000 }
        )
        .toBe(0);

      for (const member of crowd) {
        const ids = burstMessagesOf(member, liveChannelId).map(({ id }) => id);

        expect(ids, `${member.name} got a message twice`).toHaveLength(
          totalBurst
        );
        expect(new Set(ids).size).toBe(totalBurst);
      }
    });

    await test.step('every page shows the burst in order, once each', async () => {
      // the server's order, which is what every page has to agree on however the messages
      // reached it
      const expectedOrder = burstMessagesOf(firstMember, liveChannelId)
        .toSorted((a, b) => a.createdAt - b.createdAt || a.id - b.id)
        .map(tokenOf);

      for (const { label, page, link } of observers) {
        if (!link) {
          await expect
            .poll(() => burstTokensOnPage(page), { timeout: 60_000 })
            .toEqual(expectedOrder);

          continue;
        }

        // the dropped observer may only have reloaded the newest page of history after it
        // reconnected, so it can show less than the whole burst. what it shows has to be the
        // newest messages, in order, with no gap in the middle and nothing twice
        await expect
          .poll(
            async () => {
              const shown = await burstTokensOnPage(page);
              const newest = expectedOrder.slice(
                expectedOrder.length - shown.length
              );

              return (
                shown.length > 0 &&
                shown.every((token, index) => token === newest[index])
              );
            },
            { timeout: 60_000, message: `${label} shows a gap or a double` }
          )
          .toBe(true);
      }

      await expectNobodyTyping(observers);
    });

    await test.step(`someone typing by hand still reaches all ${CROWD_SIZE}`, async () => {
      const handTyped = `typed by hand ${RUN_ID}`;

      await sendMessage(observers[0]!.page, handTyped);

      await expect
        .poll(
          () =>
            crowd.filter(
              ({ received }) =>
                !received.some(({ content }) => content?.includes(handTyped))
            ).length,
          { timeout: 30_000 }
        )
        .toBe(0);

      await expectOnEveryObserver(observers, (page) =>
        expect(messageByText(page, handTyped)).toHaveCount(1, {
          timeout: 15_000
        })
      );
    });

    // rate limits on the typing signal would make people vanish from the indicator under load
    // without any visible error, so they are checked last, once everything has been sent
    expect(crowd.flatMap(({ failures }) => failures)).toEqual([]);
  } finally {
    crowd.forEach((member) => member.disconnect());

    await Promise.all(
      observers.map(({ context }) =>
        context.close().catch(() => {
          // already gone, nothing to clean up
        })
      )
    );
  }
});
