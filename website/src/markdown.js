import { marked } from 'marked';

marked.use({
  gfm: true,
  breaks: false,
  mangle: false,
  headerIds: true
});

export function stripFrontmatter(raw) {
  if (!raw.startsWith('---')) {
    return raw.trim();
  }

  const end = raw.indexOf('\n---', 3);
  if (end === -1) {
    return raw.trim();
  }

  return raw.slice(end + 4).trim();
}

function sanitizeLocalMarkdownHtml(html) {
  return html
    .replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, '')
    .replace(/\son[a-z]+\s*=\s*"[^"]*"/gi, '')
    .replace(/\son[a-z]+\s*=\s*'[^']*'/gi, '')
    .replace(/href\s*=\s*"javascript:[^"]*"/gi, 'href="#"')
    .replace(/href\s*=\s*'javascript:[^']*'/gi, "href='#'");
}

export function markdownToHtml(raw) {
  const markdown = stripFrontmatter(raw);
  const html = marked.parse(markdown);
  return sanitizeLocalMarkdownHtml(html);
}

export function firstHeading(raw, fallback) {
  const markdown = stripFrontmatter(raw);
  const match = markdown.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : fallback;
}
