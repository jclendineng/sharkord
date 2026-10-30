// a CI runner signs with a development certificate it makes for itself and throws away, and the
// account only holds a few. the workflow saves the account's certificates before it builds and
// revokes the ones that appeared since once it is done:
//   bun apps/ios/scripts/ci-certificates.ts --save certificates.json
//   bun apps/ios/scripts/ci-certificates.ts --revoke-new certificates.json
import { parseArgs } from "node:util";
import { asc } from "./asc";

const { values } = parseArgs({
  options: {
    save: { type: "string" },
    "revoke-new": { type: "string" },
  },
});

type TCertificates = {
  data: { id: string; attributes: { name: string } }[];
};

const developmentCertificates = async () => {
  const certificates: TCertificates = await asc(
    "/certificates?filter[certificateType]=DEVELOPMENT&limit=200&fields[certificates]=name",
  );

  return certificates.data;
};

const certificates = await developmentCertificates();

if (values.save) {
  await Bun.write(
    values.save,
    JSON.stringify(certificates.map(({ id }) => id)),
  );
  console.log(`saved ${certificates.length} development certificates`);
} else if (values["revoke-new"]) {
  const savedFile = Bun.file(values["revoke-new"]);
  const saved: string[] = await savedFile.json();
  const added = certificates.filter(({ id }) => !saved.includes(id));

  for (const certificate of added) {
    await asc(`/certificates/${certificate.id}`, "DELETE");
    console.log(`revoked ${certificate.attributes.name} (${certificate.id})`);
  }

  console.log(`revoked ${added.length} new development certificates`);
} else {
  console.error("needs --save or --revoke-new and a file");
  process.exit(1);
}
