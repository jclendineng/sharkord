# Server changes

Record of the changes made in `apps/server` during the iOS audit on 2026-10-21.

## Default role security

`src/routers/roles/set-default-role.ts`

- The route now rejects `OWNER_ROLE_ID` with a `FORBIDDEN` error and the message
  `The owner role cannot be the default role`.
- The check runs after the role is loaded and before the transaction that moves
  the default flag.
- Reason: everyone who joins a server gets the default role, so making the
  owner role the default would have given every new account the owner's
  permissions.

`src/routers/__tests__/roles.test.ts`

- Added a test that sets the owner role as the default and expects the error.
- The test also verifies that the owner role is still not the default
  afterwards.

## Verification

- `bun test src/routers/__tests__/roles.test.ts`: 30 pass, 0 fail.
- `bun test` in `apps/server`: 2016 pass, 0 fail, 84 files.
- `bun run magic` from the repository root: exit 0, only pre-existing lint
  warnings.
- No schema or migration changes.
