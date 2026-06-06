export const escapeRegExp = value =>
  value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export const highlightSearchTerm = (
  html = '',
  term = '',
  highlightClass = ''
) => {
  const searchTerm = term.trim();
  if (!searchTerm) return html;

  const template = document.createElement('template');
  template.innerHTML = html;
  const pattern = new RegExp(`(${escapeRegExp(searchTerm)})`, 'gi');
  const walker = document.createTreeWalker(
    template.content,
    window.NodeFilter.SHOW_TEXT
  );
  const textNodes = [];

  while (walker.nextNode()) {
    textNodes.push(walker.currentNode);
  }

  textNodes.forEach(textNode => {
    const text = textNode.nodeValue;
    if (!pattern.test(text)) return;

    pattern.lastIndex = 0;
    const fragment = document.createDocumentFragment();
    let lastIndex = 0;

    text.replace(pattern, (match, _captured, offset) => {
      fragment.append(document.createTextNode(text.slice(lastIndex, offset)));

      const highlight = document.createElement('span');
      highlight.className = highlightClass;
      highlight.textContent = match;
      fragment.append(highlight);

      lastIndex = offset + match.length;
      return match;
    });

    fragment.append(document.createTextNode(text.slice(lastIndex)));
    textNode.replaceWith(fragment);
  });

  return template.innerHTML;
};
