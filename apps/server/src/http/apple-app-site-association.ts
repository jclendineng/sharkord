import http from 'http';

// the sharkord ios app, team and bundle id, which ios checks this file for before it opens the
// server's invite links straight in the app rather than the browser
const IOS_APP_ID = 'KNSS87R6RR.com.sharkord.ios';

const ASSOCIATION = {
  applinks: {
    details: [
      {
        appIDs: [IOS_APP_ID],
        // only invite links, everything else on the server still opens in the browser
        components: [{ '?': { invite: '?*' }, comment: 'invite links' }]
      }
    ]
  }
};

const appleAppSiteAssociationRouteHandler = async (
  _req: http.IncomingMessage,
  res: http.ServerResponse
) => {
  res.writeHead(200, {
    'Content-Type': 'application/json',
    'Cache-Control': 'public, max-age=3600'
  });
  res.end(JSON.stringify(ASSOCIATION));
};

export { appleAppSiteAssociationRouteHandler };
