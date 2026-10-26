// takes an uploaded build through TestFlight: waits for processing, sets the tester notes, adds
// it to the Public group, submits it for beta review and expires the older builds of the same
// platform. run from the repo root after the upload:
//   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=AuthKey.p8 \
//   bun apps/ios/scripts/testflight.ts --platform MAC_OS --build 202610261750 --notes notes.txt
import { createPrivateKey, sign } from "node:crypto";
import { parseArgs } from "node:util";

const APP_ID = "6822132167";
const PUBLIC_GROUP_ID = "a6810676-0010-488e-bdc4-56bd4ec4088f";
const API = "https://api.appstoreconnect.apple.com/v1";

const { values } = parseArgs({
  options: {
    platform: { type: "string" },
    build: { type: "string" },
    notes: { type: "string" },
  },
});

const { platform, build, notes } = values;
const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH } = process.env;

if (!platform || !build || !ASC_KEY_ID || !ASC_ISSUER_ID || !ASC_KEY_PATH) {
  console.error(
    "needs --platform (IOS or MAC_OS), --build and ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH",
  );
  process.exit(1);
}

const keyFile = Bun.file(ASC_KEY_PATH);
const key = createPrivateKey(await keyFile.text());

const token = () => {
  const encode = (value: object) => {
    const json = Buffer.from(JSON.stringify(value));

    return json.toString("base64url");
  };
  const now = Math.floor(Date.now() / 1000);
  const body = `${encode({ alg: "ES256", kid: ASC_KEY_ID, typ: "JWT" })}.${encode(
    {
      iss: ASC_ISSUER_ID,
      iat: now,
      exp: now + 600,
      aud: "appstoreconnect-v1",
    },
  )}`;
  // jwt wants the raw r||s signature, not node's default DER
  const signature = sign("sha256", Buffer.from(body), {
    key,
    dsaEncoding: "ieee-p1363",
  });

  return `${body}.${signature.toString("base64url")}`;
};

const asc = async (path: string, method = "GET", body?: object) => {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token()}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    throw new Error(
      `${method} ${path}: ${response.status} ${await response.text()}`,
    );
  }

  if (response.status === 204) return undefined;

  return response.json();
};

const buildsPath = `/builds?filter[app]=${APP_ID}&filter[preReleaseVersion.platform]=${platform}`;

type TBuild = {
  id: string;
  attributes: { version: string; processingState: string; expired: boolean };
};

// a fresh upload reads as missing for the first minutes, then as PROCESSING
let uploaded: TBuild | undefined;

for (let attempt = 0; attempt < 90; attempt++) {
  const { data } = await asc(`${buildsPath}&filter[version]=${build}`);

  uploaded = data[0];

  if (uploaded?.attributes.processingState === "VALID") break;

  if (uploaded && uploaded.attributes.processingState !== "PROCESSING") {
    throw new Error(`build ${build} is ${uploaded.attributes.processingState}`);
  }

  console.log(
    `waiting for build ${build} (${uploaded ? "processing" : "not listed yet"})`,
  );
  await Bun.sleep(20_000);
}

if (uploaded?.attributes.processingState !== "VALID") {
  throw new Error(`build ${build} did not finish processing`);
}

if (notes) {
  const notesFile = Bun.file(notes);
  const whatsNew = await notesFile.text();
  const { data: localizations } = await asc(
    `/builds/${uploaded.id}/betaBuildLocalizations`,
  );

  if (localizations.length > 0) {
    await asc(`/betaBuildLocalizations/${localizations[0].id}`, "PATCH", {
      data: {
        type: "betaBuildLocalizations",
        id: localizations[0].id,
        attributes: { whatsNew },
      },
    });
  } else {
    await asc("/betaBuildLocalizations", "POST", {
      data: {
        type: "betaBuildLocalizations",
        attributes: { locale: "en-US", whatsNew },
        relationships: { build: { data: { type: "builds", id: uploaded.id } } },
      },
    });
  }
}

await asc(`/betaGroups/${PUBLIC_GROUP_ID}/relationships/builds`, "POST", {
  data: [{ type: "builds", id: uploaded.id }],
});

await asc("/betaAppReviewSubmissions", "POST", {
  data: {
    type: "betaAppReviewSubmissions",
    relationships: { build: { data: { type: "builds", id: uploaded.id } } },
  },
});

console.log(`build ${build} added to Public and submitted for beta review`);

const { data: older } = await asc(
  `${buildsPath}&filter[expired]=false&limit=50`,
);

for (const old of older as TBuild[]) {
  if (old.id === uploaded.id) continue;

  await asc(`/builds/${old.id}`, "PATCH", {
    data: { type: "builds", id: old.id, attributes: { expired: true } },
  });

  console.log(`expired build ${old.attributes.version}`);
}
