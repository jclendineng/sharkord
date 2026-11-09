export const isInviteExpired = (
  invite: { expiresAt: number | null },
  now: number = Date.now()
) => !!invite.expiresAt && invite.expiresAt < now;

export const isInviteUsedUp = (invite: {
  maxUses: number | null;
  uses: number;
}) => !!invite.maxUses && invite.uses >= invite.maxUses;
