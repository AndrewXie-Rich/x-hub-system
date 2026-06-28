const origin = 'https://xhubsystem.com';

function absoluteUrl(path) {
  return `${origin}${path.startsWith('/') ? path : `/${path}`}`;
}

function upsertMeta(selector, attrs) {
  let element = document.head.querySelector(selector);
  if (!element) {
    element = document.createElement('meta');
    document.head.appendChild(element);
  }
  Object.entries(attrs).forEach(([key, value]) => {
    element.setAttribute(key, value);
  });
}

function upsertLink(selector, attrs) {
  let element = document.head.querySelector(selector);
  if (!element) {
    element = document.createElement('link');
    document.head.appendChild(element);
  }
  Object.entries(attrs).forEach(([key, value]) => {
    element.setAttribute(key, value);
  });
}

export function updateDocumentSeo({ title, description, path, locale, alternates = [] }) {
  if (typeof document === 'undefined') {
    return;
  }

  const url = absoluteUrl(path);
  document.title = title;
  document.documentElement.lang = locale === 'zh' ? 'zh-CN' : 'en';

  upsertMeta('meta[name="description"]', { name: 'description', content: description });
  upsertMeta('meta[property="og:type"]', { property: 'og:type', content: 'website' });
  upsertMeta('meta[property="og:title"]', { property: 'og:title', content: title });
  upsertMeta('meta[property="og:description"]', { property: 'og:description', content: description });
  upsertMeta('meta[property="og:url"]', { property: 'og:url', content: url });
  upsertMeta('meta[property="og:site_name"]', { property: 'og:site_name', content: 'X-Hub-System' });
  upsertMeta('meta[name="twitter:card"]', { name: 'twitter:card', content: 'summary' });
  upsertMeta('meta[name="twitter:title"]', { name: 'twitter:title', content: title });
  upsertMeta('meta[name="twitter:description"]', { name: 'twitter:description', content: description });
  upsertLink('link[rel="canonical"]', { rel: 'canonical', href: url });

  document.head.querySelectorAll('link[data-xhub-alternate="true"]').forEach((element) => element.remove());
  alternates.forEach(({ hrefLang, path: alternatePath }) => {
    const element = document.createElement('link');
    element.setAttribute('rel', 'alternate');
    element.setAttribute('hreflang', hrefLang);
    element.setAttribute('href', absoluteUrl(alternatePath));
    element.setAttribute('data-xhub-alternate', 'true');
    document.head.appendChild(element);
  });
}

export function originUrl(path) {
  return absoluteUrl(path);
}
