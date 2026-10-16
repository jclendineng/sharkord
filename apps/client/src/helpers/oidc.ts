import { getUrlFromServer } from './get-file-url';
import {
  getSessionStorageItem,
  SessionStorageKey,
  setSessionStorageItem
} from './storage';

const isOidcAutoRedirectSuppressed = () =>
  getSessionStorageItem(SessionStorageKey.OIDC_NO_AUTO_REDIRECT) === 'true';

const suppressOidcAutoRedirect = () =>
  setSessionStorageItem(SessionStorageKey.OIDC_NO_AUTO_REDIRECT, 'true');

const getOidcHandoffCode = () =>
  new URLSearchParams(window.location.hash.slice(1)).get('oidc');

// an invite link's code goes along, so sso can make an account on a server closed to new users
const startOidcLogin = () => {
  suppressOidcAutoRedirect();

  const loginUrl = new URL(`${getUrlFromServer()}/oidc/login`);
  const invite = new URLSearchParams(window.location.search).get('invite');

  if (invite) {
    loginUrl.searchParams.set('invite', invite);
  }

  window.location.href = loginUrl.toString();
};

export {
  getOidcHandoffCode,
  isOidcAutoRedirectSuppressed,
  startOidcLogin,
  suppressOidcAutoRedirect
};
