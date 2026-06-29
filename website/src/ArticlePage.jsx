import React, { useEffect, useMemo, useState } from 'react';
import { Button, Divider, Space, Tag, Typography } from '@douyinfe/semi-ui';
import { IconArrowLeft, IconArrowRight } from '@douyinfe/semi-icons';
import {
  docGroups,
  docOrder,
  docTitles,
  labels,
  loadDoc,
  localizedAlternates,
  localizedPath
} from './docs.js';
import { markdownToHtml } from './markdown.js';
import { updateDocumentSeo } from './seo.js';

const { Title, Paragraph, Text } = Typography;

function stripFirstHeading(raw) {
  return raw.replace(/^#\s+.+(?:\n+|$)/, '');
}

function articleBodyRaw(raw) {
  return stripFirstHeading(raw).replace(/^\s*<p class="lead">[\s\S]*?<\/p>\s*/, '');
}

function relatedDocs(locale, slug) {
  const group = docGroups.find((item) => item.slugs.includes(slug));
  const slugs = group ? group.slugs : docOrder;
  return slugs.filter((item) => item !== slug && docTitles[locale][item]).slice(0, 3);
}

function adjacentDocs(slug) {
  const index = docOrder.indexOf(slug);
  return {
    previous: index > 0 ? docOrder[index - 1] : '',
    next: index >= 0 && index < docOrder.length - 1 ? docOrder[index + 1] : ''
  };
}

function docGroupLabel(locale, slug, fallback) {
  return docGroups.find((item) => item.slugs.includes(slug))?.label[locale] || fallback;
}

function articleSummary(raw) {
  const lead = raw.match(/<p class="lead">([\s\S]*?)<\/p>/);
  const source = lead ? lead[1] : stripFirstHeading(raw).split('\n\n')[0] || '';
  return source
    .replace(/<[^>]+>/g, ' ')
    .replace(/\[([^\]]+)]\([^)]+\)/g, '$1')
    .replace(/[*_`#>-]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanHeading(value) {
  return value
    .replace(/<[^>]+>/g, '')
    .replace(/\[([^\]]+)]\([^)]+\)/g, '$1')
    .replace(/[`*_]/g, '')
    .trim();
}

function slugifyHeading(value, fallback) {
  const slug = value
    .toLowerCase()
    .replace(/&[a-z]+;/g, '')
    .replace(/[^a-z0-9\u4e00-\u9fff]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug || fallback;
}

function articleMarkdownAndToc(raw) {
  const used = new Map();
  const toc = [];
  const markdown = articleBodyRaw(raw).replace(/^(#{2,3})\s+(.+)$/gm, (full, marks, heading) => {
    const title = cleanHeading(heading);
    const fallback = `section-${toc.length + 1}`;
    const base = slugifyHeading(title, fallback);
    const count = used.get(base) || 0;
    used.set(base, count + 1);
    const id = count ? `${base}-${count + 1}` : base;
    toc.push({ id, title, depth: marks.length });
    return `${marks} <span id="${id}" class="article-anchor"></span>${heading}`;
  });

  return { markdown, toc };
}

function ArticleLoading({ locale }) {
  const l = labels[locale];
  return (
    <main className="article-shell">
      <div className="not-found">
        <Title heading={2}>{l.loadingTitle}</Title>
        <Paragraph>{l.loadingBody}</Paragraph>
      </div>
    </main>
  );
}

export { ArticleLoading };

export default function ArticlePage({ locale, slug, SmartLink, navigateTo }) {
  const l = labels[locale];
  const related = relatedDocs(locale, slug);
  const adjacent = adjacentDocs(slug);
  const groupLabel = docGroupLabel(locale, slug, l.docsTitle);
  const [raw, setRaw] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setRaw(null);
    loadDoc(locale, slug)
      .then((content) => {
        if (!cancelled) {
          setRaw(content || '');
        }
      })
      .catch(() => {
        if (!cancelled) {
          setRaw('');
        }
      });
    return () => {
      cancelled = true;
    };
  }, [locale, slug]);

  const { html, summary, toc } = useMemo(() => {
    if (!raw) {
      return { html: '', summary: '', toc: [] };
    }
    const article = articleMarkdownAndToc(raw);
    return {
      html: markdownToHtml(article.markdown),
      summary: articleSummary(raw),
      toc: article.toc
    };
  }, [raw]);

  useEffect(() => {
    if (!raw) {
      return;
    }
    updateDocumentSeo({
      title: `${docTitles[locale][slug] || slug} | X-Hub-System`,
      description: summary || l.notFoundBody,
      path: localizedPath(locale, slug),
      locale,
      alternates: localizedAlternates(slug)
    });
  }, [l.notFoundBody, locale, raw, slug, summary]);

  if (raw === null) {
    return <ArticleLoading locale={locale} />;
  }

  if (!raw) {
    return (
      <main className="article-shell">
        <div className="not-found">
          <Title heading={2}>{l.notFoundTitle}</Title>
          <Paragraph>{l.notFoundBody}</Paragraph>
          <Button theme="solid" type="primary" onClick={() => navigateTo(localizedPath(locale))}>
            {l.articleBack}
          </Button>
        </div>
      </main>
    );
  }

  return (
    <main className="article-shell">
      <aside className="article-nav" aria-label={l.docsTitle}>
        <SmartLink className="article-back" href={localizedPath(locale)}>
          {l.articleBack}
        </SmartLink>
        <Divider margin="16px" />
        {docGroups.map((group) => (
          <div className="article-nav__group" key={group.key}>
            <span className="article-nav__group-title">{group.label[locale]}</span>
            {group.slugs.map((item) => {
              const active = item === slug;
              return (
                <SmartLink
                  className={active ? 'article-nav__item article-nav__item--active' : 'article-nav__item'}
                  href={localizedPath(locale, item)}
                  key={item}
                >
                  {docTitles[locale][item]}
                </SmartLink>
              );
            })}
          </div>
        ))}
      </aside>
      <article className="article-card">
        <header className="article-hero">
          <Space wrap>
            <Tag color="teal" shape="circle">
              {groupLabel}
            </Tag>
            <Tag color="white" shape="circle">
              {l.localeName}
            </Tag>
          </Space>
          <Title heading={1}>{docTitles[locale][slug]}</Title>
          {summary ? <Paragraph spacing="extended">{summary}</Paragraph> : null}
        </header>
        <div className={toc.length ? 'article-main article-main--with-toc' : 'article-main'}>
          <div className="article-body" dangerouslySetInnerHTML={{ __html: html }} />
          {toc.length ? (
            <nav className="article-toc" aria-label={l.onThisPage}>
              <Text className="eyebrow">{l.onThisPage}</Text>
              <div className="article-toc__links">
                {toc.map((item) => (
                  <a className={`article-toc__link article-toc__link--depth-${item.depth}`} href={`#${item.id}`} key={item.id}>
                    {item.title}
                  </a>
                ))}
              </div>
            </nav>
          ) : null}
        </div>
        <footer className="article-related">
          <div className="article-pager">
            {adjacent.previous ? (
              <SmartLink className="article-pager__link" href={localizedPath(locale, adjacent.previous)}>
                <IconArrowLeft />
                <span className="article-pager__copy">
                  <span className="article-pager__label">{l.previousDoc}</span>
                  <strong className="article-pager__title">{docTitles[locale][adjacent.previous]}</strong>
                </span>
              </SmartLink>
            ) : null}
            {adjacent.next ? (
              <SmartLink className="article-pager__link article-pager__link--next" href={localizedPath(locale, adjacent.next)}>
                <span className="article-pager__copy">
                  <span className="article-pager__label">{l.nextDoc}</span>
                  <strong className="article-pager__title">{docTitles[locale][adjacent.next]}</strong>
                </span>
                <IconArrowRight />
              </SmartLink>
            ) : null}
          </div>
          <Text className="eyebrow">{l.relatedDocs}</Text>
          <div className="article-related__grid">
            {related.map((item) => (
              <SmartLink className="article-related__link" href={localizedPath(locale, item)} key={item}>
                <span>{docGroupLabel(locale, item, l.docsTitle)}</span>
                <strong>{docTitles[locale][item]}</strong>
                <IconArrowRight />
              </SmartLink>
            ))}
          </div>
        </footer>
      </article>
    </main>
  );
}
