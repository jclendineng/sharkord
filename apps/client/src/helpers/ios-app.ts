// the public beta until the app is on the app store
export const IOS_APP_URL = 'https://testflight.apple.com/join/svXFDNEK';

// an ipad's safari asks for the desktop site and says it is a mac, only its touch screen gives it away
export const isIosDevice =
  /iPhone|iPad|iPod/.test(navigator.userAgent) ||
  (navigator.userAgent.includes('Macintosh') && navigator.maxTouchPoints > 1);
