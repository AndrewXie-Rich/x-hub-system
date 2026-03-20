# X-Hub Website

This directory contains the VitePress-based public website for X-Hub-System.

## Local Development

Install dependencies:

```bash
cd website
npm install
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

## Publishing

This repository now includes a GitHub Pages workflow at:

- `.github/workflows/website-pages.yml`

The workflow builds the VitePress site from `website/` and publishes
`website/.vitepress/dist` to GitHub Pages.

### Custom Domain

This site now includes `website/public/CNAME`, so the built Pages artifact will
carry the primary custom domain:

- `xhubsystem.com`

After the first successful Pages deployment, finish the binding in the
repository settings:

1. Open `Settings -> Pages`
2. Set the custom domain to `xhubsystem.com`
3. Enable HTTPS after DNS finishes propagating

For DNS, GitHub's current apex-domain guidance is:

- add `A` records for `xhubsystem.com` pointing to:
  - `185.199.108.153`
  - `185.199.109.153`
  - `185.199.110.153`
  - `185.199.111.153`
- optionally add `AAAA` records for IPv6:
  - `2606:50c0:8000::153`
  - `2606:50c0:8001::153`
  - `2606:50c0:8002::153`
  - `2606:50c0:8003::153`
- set `www.xhubsystem.com` as a `CNAME` to:
  - `andrewxie-rich.github.io`

GitHub recommends configuring both the apex domain and the `www` variant.
If you keep `xhubsystem.com` as the primary domain in Pages settings, GitHub
should redirect `www.xhubsystem.com` to the apex once DNS is correct.

References:

- `https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site`
- `https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages`

## Content Source

The site is intentionally the public narrative layer, not a full mirror of the repository.

Primary source documents:

- `README.md`
- `x-hub/README.md`
- `x-terminal/README.md`
- `docs/WORKING_INDEX.md`
- `docs/whitepapers/`
