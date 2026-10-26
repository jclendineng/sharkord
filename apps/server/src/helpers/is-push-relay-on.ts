import { config } from '../config';

// the relay needs both: an address from whoever runs the server, and the admins not having
// turned it off for those who would rather no third party carried their notifications
const isPushRelayOn = ({ pushRelayEnabled }: { pushRelayEnabled: boolean }) =>
  !!config.push.relayUrl && pushRelayEnabled;

export { isPushRelayOn };
