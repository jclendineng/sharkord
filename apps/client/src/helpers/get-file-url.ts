import type { TFile } from '@sharkord/shared';
import { getFileToken } from './file-tokens';

const getHostFromServer = () => {
  if (import.meta.env.MODE === 'development') {
    return 'localhost:4991';
  }

  return window.location.host;
};

const getUrlFromServer = () => {
  if (import.meta.env.MODE === 'development') {
    return 'http://localhost:4991';
  }

  const host = window.location.host;
  const currentProtocol = window.location.protocol;

  const finalUrl = `${currentProtocol}//${host}`;

  return finalUrl;
};

const getFileUrl = (file: TFile | undefined | null) => {
  if (!file) return '';

  const url = getUrlFromServer();

  let baseUrl = `${url}/public/${encodeURIComponent(file.name)}`;

  const token = getFileToken(file);

  if (token) {
    baseUrl += `?accessToken=${token.accessToken}`;

    if (token.expiresAt) {
      baseUrl += `&expires=${token.expiresAt}`;
    }
  }

  return baseUrl;
};

export { getFileUrl, getHostFromServer, getUrlFromServer };
