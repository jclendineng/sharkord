// the App Store Connect API, signed with the key in ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH
import { createPrivateKey, sign } from "node:crypto";

const API = "https://api.appstoreconnect.apple.com/v1";

const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH } = process.env;

if (!ASC_KEY_ID || !ASC_ISSUER_ID || !ASC_KEY_PATH) {
  console.error("needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH");
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

export const asc = async (path: string, method = "GET", body?: object) => {
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
