export const showBadgeOnFavicon = () => {
  const favicons = document.querySelectorAll('.favicon');

  favicons.forEach(favicon => {
    const newFileName = `/favicon-badge-${favicon.sizes[[0]]}.png`;
    favicon.href = newFileName;
  });
};

export const initFaviconSwitcher = () => {
  const favicons = document.querySelectorAll('.favicon');

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      favicons.forEach(favicon => {
        favicon.href =
          favicon.dataset.accountHref || `/favicon-${favicon.sizes[[0]]}.png`;
      });
    }
  });
};
