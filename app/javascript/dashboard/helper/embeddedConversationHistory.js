const FROM_EMBEDDED_KEY = 'fromEmbedded';

export const pushEmbedded = (router, to, fromEmbedded = false) =>
  router.push({ ...to, state: { [FROM_EMBEDDED_KEY]: fromEmbedded } });

export const goBackEmbedded = (router, backRoute) =>
  window.history.state?.[FROM_EMBEDDED_KEY]
    ? router.go(-1)
    : router.push(backRoute);
