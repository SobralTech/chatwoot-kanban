const DEPTH_KEY = 'embeddedDepth';

export const currentEmbeddedDepth = () =>
  Number(window.history.state?.[DEPTH_KEY] ?? 0);

export const pushEmbedded = (router, to, depth) =>
  router.push({ ...to, state: { [DEPTH_KEY]: depth } });

export const goBackEmbedded = (router, backRoute) =>
  currentEmbeddedDepth() > 0 ? router.go(-1) : router.push(backRoute);
