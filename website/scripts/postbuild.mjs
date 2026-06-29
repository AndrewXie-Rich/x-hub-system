import { copyFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { docOrder, localizedAlternates, localizedPath } from '../src/docs.js';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dist = join(root, '.vitepress', 'dist');
const origin = 'https://xhubsystem.com';

function absoluteUrl(pathname) {
  return `${origin}${pathname.startsWith('/') ? pathname : `/${pathname}`}`;
}

function sitemapEntry(pathname, slug) {
  const alternates = localizedAlternates(slug)
    .map(
      (item) =>
        `    <xhtml:link rel="alternate" hreflang="${item.hrefLang}" href="${absoluteUrl(item.path)}" />`
    )
    .join('\n');
  return `  <url>
    <loc>${absoluteUrl(pathname)}</loc>
${alternates}
  </url>`;
}

async function writeRouteEntry(pathname) {
  const clean = pathname.replace(/^\/+|\/+$/g, '');
  if (!clean) {
    return;
  }
  const routeDir = join(dist, clean);
  await mkdir(routeDir, { recursive: true });
  await copyFile(join(dist, 'index.html'), join(routeDir, 'index.html'));
}

await mkdir(dist, { recursive: true });
await copyFile(join(dist, 'index.html'), join(dist, '404.html'));

const routeEntries = ['', ...docOrder].flatMap((slug) => [
  { path: localizedPath('en', slug), slug },
  { path: localizedPath('zh', slug), slug }
]);

await Promise.all(routeEntries.map((entry) => writeRouteEntry(entry.path)));

const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${routeEntries.map((entry) => sitemapEntry(entry.path, entry.slug)).join('\n')}
</urlset>
`;

const robots = `User-agent: *
Allow: /

Sitemap: ${origin}/sitemap.xml
`;

await writeFile(join(dist, 'sitemap.xml'), sitemap);
await writeFile(join(dist, 'robots.txt'), robots);
