# X-Hub Website

This directory contains the React + Semi Design public website for X-Hub-System.
The Markdown pages remain in place and are rendered through the React site as
article content.

## Local Development

Install dependencies:

```bash
cd website
npm ci
```

Run the dev server:

```bash
cd website
npm run docs:dev
```

Build the static site:

```bash
cd website
npm run docs:build
```

Preview the production build:

```bash
cd website
npm run docs:preview
```

Run the local artifact smoke:

```bash
cd website
npm run docs:smoke
```

The smoke verifies:

- every public English and Chinese route has a static `index.html`
- `/memory` and `/zh-CN/memory` remain valid switch targets
- `404.html`, `sitemap.xml`, and `robots.txt` exist
- the public architecture SVGs in `website/public/` match the build artifact

To also check a deployed URL:

```bash
cd website
XHUB_WEBSITE_BASE_URL=https://xhubsystem.com npm run docs:smoke
```

## Publishing

The production website is Cloudflare Pages:

- project: `x-hub-system`
- domain: `https://xhubsystem.com`
- build output: `website/.vitepress/dist`

Recommended Cloudflare Pages Git settings, when the project root is the repo
root:

```bash
cd website && npm ci && npm run docs:build && npm run docs:smoke
```

Build output directory:

```text
website/.vitepress/dist
```

If the Cloudflare Pages root directory is set to `website/` instead, use:

```bash
npm ci && npm run docs:build && npm run docs:smoke
```

and set the output directory to:

```text
.vitepress/dist
```

Manual deploy, used when the Cloudflare Git build is unavailable:

```bash
cd website
npm run docs:build
npm run docs:smoke
npx wrangler pages deploy .vitepress/dist --project-name x-hub-system --branch main
```

After deploy, verify the domain and key assets:

```bash
cd website
XHUB_WEBSITE_BASE_URL=https://xhubsystem.com npm run docs:smoke
```

## GitHub Actions

`.github/workflows/website-pages.yml` is intentionally build-only. It installs
dependencies, builds the site, and runs `npm run docs:smoke`; it does not deploy
to GitHub Pages. Cloudflare Pages is the production publisher.

## Custom Domain

The production custom domain is:

- `xhubsystem.com`

DNS and SSL are managed in Cloudflare. Keep `website/public/CNAME` for
compatibility with static hosting previews, but do not treat GitHub Pages as the
production publisher.

## Content Source

The site is intentionally the public narrative layer, not a full mirror of the repository.

Primary source documents:

- `README.md`
- `x-hub/README.md`
- `x-terminal/README.md`
- `docs/WORKING_INDEX.md`
- `docs/whitepapers/`
