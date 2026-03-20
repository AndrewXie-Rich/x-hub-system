import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import HeroConsole from './components/HeroConsole.vue'
import SiteFooter from './components/SiteFooter.vue'
import './custom.css'

export default {
  extends: DefaultTheme,
  enhanceApp(ctx) {
    DefaultTheme.enhanceApp?.(ctx)
    ctx.app.component('HeroConsole', HeroConsole)
  },
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'layout-bottom': () => h(SiteFooter)
    })
  }
}
