import React, { lazy, Suspense, useEffect, useMemo, useState } from 'react';
import {
  BackTop,
  Button,
  Card,
  Descriptions,
  Layout,
  Nav,
  Space,
  SideSheet,
  TabPane,
  Tabs,
  Tag,
  Timeline,
  Typography
} from '@douyinfe/semi-ui';
import {
  IconArrowRight,
  IconArchive,
  IconBookOpenStroked,
  IconCode,
  IconComponent,
  IconGithubLogo,
  IconGlobe,
  IconKey,
  IconMenu,
  IconRoute,
  IconSafeStroked,
  IconServer,
  IconShield,
  IconTerminal,
  IconTickCircle
} from '@douyinfe/semi-icons';
import {
  docGroups,
  docTitles,
  labels,
  localizedAlternates,
  localizedPath,
  prefetchDoc,
  releasesUrl,
  repoUrl,
  siteCopy
} from './docs.js';
import { updateDocumentSeo } from './seo.js';

const { Header, Content, Footer } = Layout;
const { Title, Paragraph, Text } = Typography;
const ArticlePage = lazy(() => import('./ArticlePage.jsx'));

const iconBySlug = {
  family: IconSafeStroked,
  team: IconServer,
  'why-now': IconTickCircle,
  security: IconShield,
  architecture: IconRoute,
  constitution: IconSafeStroked,
  'local-first': IconServer,
  skills: IconKey,
  'x-terminal': IconTerminal,
  memory: IconArchive,
  'coding-runtime': IconCode
};

function normalizePath(pathname) {
  const decoded = decodeURI(pathname || '/');
  return decoded.replace(/\/+$/, '') || '/';
}

function routeFromPath(pathname) {
  const path = normalizePath(pathname);
  const isZh = path === '/zh-CN' || path.startsWith('/zh-CN/');
  const locale = isZh ? 'zh' : 'en';
  const prefixless = isZh ? path.replace(/^\/zh-CN\/?/, '') : path.replace(/^\//, '');
  const slug = prefixless || '';
  return { locale, slug, path };
}

function navigateTo(href) {
  if (!href || href.startsWith('http') || href.startsWith('mailto:')) {
    return false;
  }
  window.history.pushState({}, '', href);
  window.dispatchEvent(new Event('xhub:navigation'));
  window.scrollTo({ top: 0, behavior: 'smooth' });
  return true;
}

function scrollToSection(id) {
  const target = document.getElementById(id);
  if (target) {
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
}

function prefetchRoute(href) {
  if (!href || href.startsWith('http') || href.startsWith('mailto:')) {
    return;
  }
  const { locale, slug } = routeFromPath(href);
  prefetchDoc(locale, slug);
}

function SmartLink({ href, children, className, ariaLabel, onNavigate }) {
  const external = href?.startsWith('http');
  return (
    <a
      aria-label={ariaLabel}
      className={className}
      href={href}
      rel={external ? 'noreferrer' : undefined}
      target={external ? '_blank' : undefined}
      onFocus={() => prefetchRoute(href)}
      onMouseEnter={() => prefetchRoute(href)}
      onClick={(event) => {
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
          return;
        }
        if (navigateTo(href)) {
          event.preventDefault();
          onNavigate?.();
        }
      }}
    >
      {children}
    </a>
  );
}

function useRoute() {
  const [route, setRoute] = useState(() => routeFromPath(window.location.pathname));

  useEffect(() => {
    const update = () => setRoute(routeFromPath(window.location.pathname));
    window.addEventListener('popstate', update);
    window.addEventListener('xhub:navigation', update);
    return () => {
      window.removeEventListener('popstate', update);
      window.removeEventListener('xhub:navigation', update);
    };
  }, []);

  return route;
}

function navItemsForLocale(locale) {
  const l = labels[locale];
  return [
    { itemKey: 'home', text: l.home, icon: <IconShield /> },
    ...l.nav.map(([slug, text]) => {
      const Icon = iconBySlug[slug] || IconBookOpenStroked;
      return { itemKey: slug, text, icon: <Icon /> };
    })
  ];
}

function selectNavItem(locale, itemKey) {
  const slug = itemKey === 'home' ? '' : itemKey;
  navigateTo(localizedPath(locale, slug));
}

function switchableSlug(locale, slug) {
  if (!slug || slug === 'index') {
    return '';
  }
  return docTitles[locale]?.[slug] ? slug : '';
}

function SiteHeader({ locale, slug }) {
  const l = labels[locale];
  const [menuVisible, setMenuVisible] = useState(false);
  const otherLocale = locale === 'zh' ? 'en' : 'zh';
  const otherHref = localizedPath(otherLocale, switchableSlug(otherLocale, slug));
  const selectedKey = slug && slug !== 'index' ? slug : 'home';
  const navItems = useMemo(() => navItemsForLocale(locale), [locale]);

  return (
    <Header className="site-header">
      <div className="site-header__inner">
        <SmartLink href={localizedPath(locale)} className="brand">
          <img src="/favicon.svg" alt="" />
          <span>{l.brand}</span>
        </SmartLink>

        <Nav
          className="top-nav"
          mode="horizontal"
          selectedKeys={[selectedKey]}
          items={navItems}
          onSelect={(data) => selectNavItem(locale, data.itemKey)}
        />

        <div className="header-actions">
          <Button
            aria-label={l.github}
            icon={<IconGithubLogo />}
            theme="borderless"
            onClick={() => window.open(repoUrl, '_blank', 'noreferrer')}
          />
          <SmartLink className="language-link" href={otherHref} ariaLabel={l.switchLocale}>
            <IconGlobe />
            <span>{l.otherLocale}</span>
          </SmartLink>
          <Button
            className="mobile-menu-button"
            icon={<IconMenu />}
            theme="borderless"
            aria-label={l.openMenu}
            onClick={() => setMenuVisible(true)}
          />
        </div>
      </div>
      <SideSheet
        bodyStyle={{ padding: 0 }}
        closeOnEsc
        onCancel={() => setMenuVisible(false)}
        placement="right"
        title={l.brand}
        visible={menuVisible}
        width={320}
      >
        <Nav
          className="mobile-nav"
          items={navItems}
          selectedKeys={[selectedKey]}
          onSelect={(data) => {
            setMenuVisible(false);
            selectNavItem(locale, data.itemKey);
          }}
        />
        <div className="mobile-nav__actions">
          <SmartLink
            className="mobile-action-link"
            href={otherHref}
            ariaLabel={l.switchLocale}
            onNavigate={() => setMenuVisible(false)}
          >
            <IconGlobe />
            <span>{l.otherLocale}</span>
          </SmartLink>
          <Button block icon={<IconGithubLogo />} onClick={() => window.open(repoUrl, '_blank', 'noreferrer')}>
            {l.github}
          </Button>
        </div>
      </SideSheet>
    </Header>
  );
}

function Hero({ copy, locale }) {
  return (
    <section className="hero">
      <div className="hero__overlay" />
      <div className="hero__content">
        <Tag color="teal" shape="circle" size="large" type="solid" prefixIcon={<IconShield />}>
          {copy.heroEyebrow}
        </Tag>
        <Title className="hero__title">{copy.heroTitle}</Title>
        <Paragraph className="hero__body" spacing="extended">
          {copy.heroBody}
        </Paragraph>
        <Space wrap>
          <Button
            icon={<IconGithubLogo />}
            iconPosition="right"
            size="large"
            theme="solid"
            type="primary"
            onClick={() => window.open(repoUrl, '_blank', 'noreferrer')}
          >
            {copy.primaryCta}
          </Button>
          <Button
            icon={<IconArrowRight />}
            iconPosition="right"
            size="large"
            theme="solid"
            type="tertiary"
            onClick={() => scrollToSection('how-it-works')}
          >
            {copy.secondaryCta}
          </Button>
        </Space>
      </div>
      <div className="hero__status" aria-label="Runtime posture">
        {copy.proof.map(([label, body]) => (
          <div className="status-row" key={label}>
            <IconTickCircle />
            <div>
              <strong>{label}</strong>
              <span>{body}</span>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function FlowSection({ copy }) {
  const timelineData = copy.governanceSteps.map(([label, body, type], index) => ({
    time: `0${index + 1}`,
    type,
    content: (
      <div className="timeline-content">
        <strong>{label}</strong>
        <span>{body}</span>
      </div>
    )
  }));

  return (
    <section className="section flow-section" id="how-it-works">
      <div className="section-head">
        <Text className="eyebrow">{copy.preview}</Text>
        <Title heading={2}>{copy.flowTitle}</Title>
        <Paragraph spacing="extended">{copy.previewBody}</Paragraph>
      </div>
      <Card className="timeline-card" bordered headerLine={false} title={copy.governanceTitle}>
        <Timeline dataSource={timelineData} />
      </Card>
    </section>
  );
}

function RuntimeSnapshot({ copy }) {
  const [layerLabel, roleLabel, responsibilityLabel, postureLabel] = copy.runtimeFieldLabels;

  return (
    <section className="section runtime-section">
      <div className="section-head section-head--wide">
        <Text className="eyebrow">{copy.runtimeSnapshotLabel}</Text>
        <Title heading={2}>{copy.runtimeSnapshotTitle}</Title>
        <Paragraph spacing="extended">{copy.runtimeSnapshotBody}</Paragraph>
      </div>
      <div className="runtime-grid">
        {copy.runtimeRows.map(([layer, role, responsibility, posture]) => (
          <Card bordered className="runtime-card" headerLine={false} key={layer} shadows="hover">
            <Descriptions
              align="plain"
              className="runtime-description"
              column={2}
              data={[
                {
                  key: layerLabel,
                  value: <Text strong>{layer}</Text>
                },
                {
                  key: postureLabel,
                  value: (
                    <Tag color={posture === 'Compat' || posture === '兼容' ? 'amber' : 'teal'} shape="circle">
                      {posture}
                    </Tag>
                  )
                },
                {
                  key: roleLabel,
                  value: role,
                  span: 2
                },
                {
                  key: responsibilityLabel,
                  value: responsibility,
                  span: 2
                }
              ]}
              layout="horizontal"
            />
          </Card>
        ))}
      </div>
      <div className="runtime-highlights">
        {copy.flow.map(([label, body]) => (
          <div className="runtime-highlight" key={label}>
            <IconComponent />
            <strong>{label}</strong>
            <span>{body}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function Capabilities({ copy, locale }) {
  return (
    <section className="section">
      <div className="section-head section-head--wide">
        <Text className="eyebrow">{copy.controlSurfaceLabel}</Text>
        <Title heading={2}>{copy.capabilitiesTitle}</Title>
        <Paragraph spacing="extended">{copy.capabilitiesBody}</Paragraph>
      </div>
      <div className="capability-grid">
        {copy.capabilities.map(([label, title, body, slug]) => {
          const Icon = iconBySlug[slug] || IconBookOpenStroked;
          return (
            <Card
              key={slug}
              bordered
              className="capability-card"
              headerLine={false}
              shadows="hover"
              onClick={() => navigateTo(localizedPath(locale, slug))}
            >
              <div className="capability-card__icon">
                <Icon />
              </div>
              <Tag color="white" size="small">
                {label}
              </Tag>
              <strong>{title}</strong>
              <p>{body}</p>
            </Card>
          );
        })}
      </div>
    </section>
  );
}

function UseCases({ copy, locale }) {
  return (
    <section className="section section--contrast">
      <div className="section-head section-head--wide">
        <Text className="eyebrow">{copy.useCasesLabel}</Text>
        <Title heading={2}>{copy.useCasesTitle}</Title>
      </div>
      <div className="audience-grid">
        {copy.audienceCards.map(([title, body, proof, slug]) => {
          const Icon = iconBySlug[slug] || IconBookOpenStroked;
          return (
            <div className="audience-card" key={slug} onClick={() => navigateTo(localizedPath(locale, slug))}>
              <div className="audience-card__head">
                <span>
                  <Icon />
                </span>
                <IconArrowRight />
              </div>
              <strong>{title}</strong>
              <p>{body}</p>
              <small>{proof}</small>
            </div>
          );
        })}
      </div>
      <div className="usecase-grid usecase-grid--compact">
        {copy.useCases.map(([label, body]) => (
          <div className="usecase-row" key={label}>
            <span>{label}</span>
            <strong>{body}</strong>
          </div>
        ))}
      </div>
    </section>
  );
}

function Diagrams({ copy }) {
  return (
    <section className="section">
      <div className="section-head section-head--wide">
        <Text className="eyebrow">{copy.diagramsLabel}</Text>
        <Title heading={2}>{copy.diagramsTitle}</Title>
        <Paragraph spacing="extended">{copy.diagramsBody}</Paragraph>
      </div>
      <div className="diagram-grid">
        <figure>
          <img
            src="/xhub_trust_control_plane.svg"
            alt="X-Hub trust and control plane"
            loading="lazy"
            decoding="async"
          />
          <figcaption>{copy.diagramOne}</figcaption>
        </figure>
        <figure>
          <img
            src="/xhub_before_after.svg"
            alt="Without X-Hub vs With X-Hub: where memory, keys, audit and policy live"
            loading="lazy"
            decoding="async"
          />
          <figcaption>{copy.diagramTwo}</figcaption>
        </figure>
      </div>
    </section>
  );
}

function DocsTabs({ locale }) {
  const l = labels[locale];
  const copy = siteCopy[locale];

  return (
    <section className="section docs-section">
      <div className="section-head section-head--wide">
        <Text className="eyebrow">{l.docsTitle}</Text>
        <Title heading={2}>{copy.docsIntro}</Title>
      </div>
      <Tabs type="line" className="docs-tabs">
        {docGroups.map((group) => (
          <TabPane tab={group.label[locale]} itemKey={group.key} key={group.key}>
            <div className="doc-link-grid">
              {group.slugs.map((slug) => (
                <SmartLink className="doc-link" href={localizedPath(locale, slug)} key={slug}>
                  <span>{docTitles[locale][slug]}</span>
                  <IconArrowRight />
                </SmartLink>
              ))}
            </div>
          </TabPane>
        ))}
      </Tabs>
    </section>
  );
}

function HomePage({ locale }) {
  const copy = siteCopy[locale];
  return (
    <>
      <Hero copy={copy} locale={locale} />
      <FlowSection copy={copy} />
      <RuntimeSnapshot copy={copy} />
      <Capabilities copy={copy} locale={locale} />
      <UseCases copy={copy} locale={locale} />
      <Diagrams copy={copy} />
      <DocsTabs locale={locale} />
    </>
  );
}

function ArticleFallback({ locale }) {
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

function SiteFooter({ locale }) {
  const l = labels[locale];
  return (
    <Footer className="site-footer">
      <div>
        <strong>X-Hub-System</strong>
        <span>Security-first Hub-governed AI execution system.</span>
      </div>
      <Space wrap>
        <SmartLink href={localizedPath(locale, 'docs')}>{l.readDocs}</SmartLink>
        <SmartLink href={repoUrl}>{l.github}</SmartLink>
        <SmartLink href={releasesUrl}>{l.releases}</SmartLink>
      </Space>
    </Footer>
  );
}

export default function App() {
  const route = useRoute();
  const { locale, slug } = route;
  const isHome = slug === '' || slug === 'index';

  useEffect(() => {
    const title = isHome
      ? locale === 'zh'
        ? 'X-Hub-System | 用户自有的 AI 执行控制平面'
        : 'X-Hub-System | User-owned AI control plane'
      : `${docTitles[locale][slug] || slug} | X-Hub-System`;
    const description = isHome
      ? siteCopy[locale].heroBody
      : `${docTitles[locale][slug] || slug} in the X-Hub-System documentation.`;
    updateDocumentSeo({
      title,
      description,
      path: localizedPath(locale, isHome ? '' : slug),
      locale,
      alternates: localizedAlternates(isHome ? '' : switchableSlug(locale, slug))
    });
  }, [isHome, locale, slug]);

  return (
    <Layout className="app-shell">
      <a className="skip-link" href="#main-content">
        {labels[locale].skipToContent}
      </a>
      <SiteHeader locale={locale} slug={slug} />
      <Content id="main-content">
        {isHome ? (
          <HomePage locale={locale} />
        ) : (
          <Suspense fallback={<ArticleFallback locale={locale} />}>
            <ArticlePage locale={locale} slug={slug} SmartLink={SmartLink} navigateTo={navigateTo} />
          </Suspense>
        )}
      </Content>
      <SiteFooter locale={locale} />
      <BackTop />
    </Layout>
  );
}
