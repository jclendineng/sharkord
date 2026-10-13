import { config } from '../config';
import { updateSettings } from '../db/mutations/server';

// with forceSignedUrls on in config.ini the stored switch is turned on too, so every file link
// carries an expiring token and the settings screens show it. it stays on if the lock is lifted
const applyForcedSignedUrls = async () => {
  if (!config.storage.forceSignedUrls) {
    return;
  }

  await updateSettings({ storageSignedUrlsEnabled: true });
};

export { applyForcedSignedUrls };
