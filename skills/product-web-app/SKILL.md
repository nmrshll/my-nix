---
schemaVersion: 1
name: product-web-app
description: >
  Builds the product's own web app: a Solid + Vite single-page application that
  consumes the workspace web design system, mounts once into a fixed-height app
  shell, and talks to the local API (or a Tauri IPC bridge) through one typed
  client. Use for app-shaped UIs — sidebars, panes, command palettes, settings,
  lists — not for landing pages, docs, or component galleries.
aliases: [spa, web-app, solid-app, app-shell, vite-app]
dependencies: [product-website, ui-design-system]
validationHints:
  - app entry imports the generated Panda sheet before the design-system stylesheet
  - every fetch goes through one typed client with ApiError and NetworkError
  - shell is fixed height with per-pane scrolling, not a scrolling document
trigger:
  providers: ['*']
  scope: system
disable_model_invocation: false
user_invocable: true
---

## Boundary

This skill covers the **product web app**: the SPA a user actually works in —
app shell, views, data layer, desktop bridge. It assumes the workspace already
has a design system; if it does not, start with `product-website` (which owns
`libs/web-design-system`, its tokens, and the Panda parity rules) and come back.

Out of scope: landing page, docs, marketing, component showcase. Those are
`product-website`.

The same UI usually has to run two ways: in a browser against a local HTTP API,
and inside a Tauri window against native IPC. Design for both from the start.

## 1. Where it lives

```
apps/<product>-web/            # standalone SPA (tally-web, taskstream-web)
apps/<product>/ui/             # SPA vendored inside a Tauri app (shepherd/ui)
apps/desktop/                  # Tauri + Vite where the desktop *is* the product
```

Pick the shape that matches how it ships:

| Shape | When | Entry |
| --- | --- | --- |
| `apps/<product>-web` | Browser-first product, desktop optional later | `index.html` + `src/main.tsx` |
| `apps/<product>/ui` | Desktop-first; the UI is a window, not a website | its own `index.html`, Tauri `frontendDist` points at `../ui/dist` |
| `apps/desktop` | One app, Tauri wrapper around Vite | `vite --port 1420 --strictPort` |

All of them are pnpm workspace members and consume the design system with
`workspace:*`. Never copy components into the app.

## 2. Build setup

- **Vite** + `vite-plugin-solid`, TypeScript, `jsx: preserve`,
  `jsxImportSource: solid-js`, `moduleResolution: bundler`, `noEmit`, strict.
- Alias `styled-system` to the app's own generated directory, because the
  design system's source imports `styled-system/*` and each project generates
  its own copy.
- Codegen runs before dev and build, never by hand:

```json
"codegen": "pnpm --filter web-design-system run codegen && panda codegen && panda cssgen --outfile styled-system/styles.css",
"predev": "pnpm run codegen",
"prebuild": "pnpm run codegen",
"dev": "vite",
"build": "vite build",
"preview": "vite preview",
"typecheck": "pnpm run codegen && tsc --noEmit"
```

```ts
// vite.config.ts
export default defineConfig({
  plugins: [solid()],
  resolve: {
    alias: { 'styled-system': fileURLToPath(new URL('./styled-system', import.meta.url)) },
  },
  server: {
    port: 5180,
    proxy: { '/api': { target: 'http://127.0.0.1:8080', changeOrigin: true } },
  },
})
```

Two Panda layouts exist in the workspace; pick per repo, not per file:

- **Per-app `panda.config.ts`** (tally-web, taskstream-web) — the app owns
  `styled-system/`. Keeps the class-parity rules local and obvious.
- **One root `panda.config.ts` + `@pandacss/vite`** (recipes-lofi) — several
  consumers share one generated directory via `pandacss({ cwd: '../..' })`.
  Cheaper with many apps; the root config must scan every consumer.

Panda settings that are not optional:

- `include` must list the app's `src/**` **and** the design system's `src/**`.
- When recipes apply variants dynamically (`<Button variant="…">`), add
  `staticCss: { recipes: '*' }` — `cssgen` cannot see those usages and the
  styles silently go missing otherwise.
- `preflight` follows the design system: `true` for a Park UI style system that
  expects it, `false` when the package ships its own reset in cascade layers.
- Keep `prefix` / `hash` / `separator` identical to the package and the site.

## 3. Entry and theming

```tsx
// src/main.tsx — order matters: Panda declares the cascade layers,
// the design system slots its reset/base into them, the app comes last.
import 'styled-system/styles.css'
import 'web-design-system/styles.css'
import './styles/app.css'
import { render } from 'solid-js/web'
import App from './App'

const root = document.getElementById('root')
if (!root) throw new Error('Missing #root')
render(() => <App />, root)
```

```html
<!-- index.html — set the theme before first paint, before the module runs -->
<html lang="en" data-theme="dark">
  <script>
    try {
      var stored = localStorage.getItem('wds-theme')
      document.documentElement.dataset.theme = stored === 'light' ? 'light' : 'dark'
    } catch (_) {}
  </script>
  <div id="root"></div>
  <script type="module" src="/src/main.tsx"></script>
```

- The theme mechanism belongs to the design system: `data-theme` attribute or a
  `.dark` class, with a storage key it names. Mirror it exactly in the inline
  script; a mismatch produces a flash, not an error.
- Add `<meta name="color-scheme" content="dark light">` so form controls and
  scrollbars follow.
- There are no Astro directives here. `client:only` / `client:visible` are for
  the docs site; the SPA mounts once into `#root`.

## 4. The shell

The app is a window, not a document. Fix the height, let panes scroll.

```css
/* src/styles/app.css */
html, body, #root { height: 100%; }
body { overflow: hidden; }              /* the page never scrolls */
#root { display: flex; flex-direction: column; }
```

```tsx
const shell = css({ display: 'flex', flexDirection: 'column', h: 'full', minH: '0', bg: 'canvas', color: 'fg.default' })
const body  = css({ display: 'flex', flex: '1', minH: '0' })
const main  = css({ flex: '1', minW: '0', overflowY: 'auto' })
```

Shapes that have worked:

| Shape | Composition |
| --- | --- |
| Product workspace | 240–260px sidebar (brand, picker, nav, auth footer) + main column with `maxW` content; full-bleed views opt out of the container |
| Desktop mirror | title bar + [nav + content] + footer bar, with a right rail and a command palette overlaid at the root |
| Settings/overview views | one `ViewShell`: header (`title`, `subtitle`, `actions`) + scrolling body of cards |

Shell rules:

- `minH: '0'` on every flex child between the viewport and a scroller, or the
  overflow never engages.
- Pane chrome is a shared module of Panda recipes (`view`, `header`, `card`,
  `rowBetween`, `gridTwo`, `field`, `chip`, `action`, `textInput`, `note`,
  `divider`), not ad-hoc classes in each view. Views import them; a new visual
  pattern goes into the design system instead.
- Overlays (toaster, dialogs, command palette) mount at the app root, not inside
  the pane that triggers them.
- Fixed-height apps that show long lists need a visible scroll region with
  `tabindex="0"` and an accessible name, same as the docs site's tables.

## 5. Navigation

No router. A discriminated union destination in the store, rendered with
`Switch`/`Match`:

```ts
type Destination =
  | { kind: 'all' }
  | { kind: 'tag'; tagId: string }
  | { kind: 'apps' } | { kind: 'integrations' } | { kind: 'automations' }
  | { kind: 'sync' } | { kind: 'settings' }
```

Why: a desktop-shaped app has in-app destinations and a history stack that does
not map to URLs, and adding React-Router-style plumbing buys nothing. If the app
genuinely needs deep links later, add a router deliberately — do not start with
one.

Navigation affordances that earn their place:

- `aria-current="page"` on the active destination.
- Number-key switching (`1`–`5`), skipped while the target is an input,
  textarea, or `contentEditable`. Register on `window`, clean up in `onCleanup`.
- `⌘K` command palette built from a `Command[]` array of `{ id, label, hint,
  run }`; filter with a `createMemo`, not an effect.
- Disabled destinations ship with a visible "Soon" badge and `title`, and the
  click handler returns early. Never a nav item that silently does nothing.

## 6. State

Two patterns, no state library:

```tsx
// App state: a store in a context provider.
const [state, setState] = createStore<AppState>({ … })
<AppProvider><App /></AppProvider>   // useApp() in every view
```

```ts
// Cross-cutting singleton (session): module scope, created in createRoot so
// it is usable outside components.
export const [session, setSession] = createRoot(() => createSignal<Session>({ status: 'local' }))
```

- Derived data is `createMemo`, not an effect that writes another signal.
- Persisted state is read once at boot into the store, and written on mutation.
- Keep mock/fixture data in one module (`mock_data.ts` / `data/seed.ts`) whose
  exported **types** are what views consume. Swapping to the API then stays
  inside that module and the client.

## 7. Data layer

Three modules, one direction: views → client → session. Views never call `fetch`.

### `api.ts` — the only fetch

```ts
const API_BASE = '/api/v1'                    // Vite dev proxy, same-origin in prod

export class ApiError extends Error {          // parsed { error: { code, message, details } }
  constructor(readonly code: string, message: string, readonly details: unknown, readonly status: number) { super(message) }
}
export class NetworkError extends Error {}     // fetch threw / body unparseable

export async function api<T>(path: string, opts: ApiOptions = {}): Promise<T> { … }
```

Rules:

- One wrapper attaches `Authorization: Bearer <token>`, sets JSON or multipart
  bodies, and turns a 401 into `handleExpired()`.
- Views branch on the stable snake_case **`code`**, never on `message` text.
  Keep an error-code → UI mapping table in the spec.
- `NetworkError` is a distinct state, not an exception to swallow: it drives an
  offline banner, a toast, or the outbox.

### `session.ts` — the auth state machine

```
restoring → signed-in | local | offline
local     → signed-in            (login / register / guest bootstrap)
signed-in → local                (sign out, or a runtime 401)
signed-in | restoring → offline  (network fault; token kept)
```

- Token in `localStorage` under a versioned key (`tally.token.v1`).
- Sign-out clears locally even when the request fails; `handleExpired()` toasts
  only if a session was actually live, so parallel 401s toast once.
- `markOffline()` keeps the token — an unreachable API is not a signed-out user.

### Around it

- `guest.ts` — stable anonymous UUID (`X-Guest-Id`), generated once, never
  deleted, lazily bootstrapped on the first action that needs ownership. Never
  at app boot: a login wall is not an onboarding flow.
- `outbox.ts` — offline queue in `localStorage`, replayed in order once a
  session exists, stopping on a hard (4xx) failure so the user can fix it, with
  a toast in both directions.
- `db.ts` — versioned local store (`tally.db.v1`) with defaults merged over
  parsed JSON, tolerant of a corrupt payload, and a no-op fallback when storage
  is unavailable (private mode). The app must still work in memory.
- `native.ts` — `isNative()` via `window.__TAURI__?.core?.invoke`; if native,
  route the same request shape through an IPC command (`native_request`) instead
  of HTTP. The transport selects itself; the views do not care.

## 8. Dev proxy and ports

- `server.proxy['/api'] → http://127.0.0.1:8080` (tally), `7080` (recipes, with
  a rewrite stripping `/api` and a `RECIPES_API_URL` override).
- Dev servers use one fixed port per app: `5173` / `5174` / `5180` for web apps,
  `1420` for a Tauri frontend, `1421` for its Playwright server.
- Tauri frontends need `strictPort: true`: `tauri.conf.json` loads exactly one
  origin, and a fallback port leaves the window blank.
- Document the backend's prerequisites in the app README: the dev shell command
  that starts db + api + web (e.g. a zellij session), and the individual
  `dev-db` / `api` scripts for people running panes by hand.

## 9. Tauri, when the app ships natively

```json
{
  "build": {
    "beforeDevCommand": "pnpm --dir ui run dev",
    "devUrl": "http://localhost:1420",
    "beforeBuildCommand": "pnpm --dir ui run build",
    "frontendDist": "../ui/dist",
    "additionalWatchFolders": ["../ui"]
  },
  "app": { "security": { "csp": "frame-ancestors 'none'" } }
}
```

- The Rust side owns data, files, and provider calls; the UI owns presentation.
  Business rules do not move into TypeScript.
- The web build must still be usable in a browser. If a feature only works
  natively, gate it on `isNative()` and say so in the UI.
- CSP stays explicit (`default-src 'self'`, `connect-src ipc:` … for full apps).
- On macOS use the background smoke for routine native checks; run a visible
  window only when the change affects what that check exercises.

## 10. Verification

Cheap and build-adjacent first — these catch most breakage:

```sh
pnpm codegen
pnpm typecheck
pnpm build
```

Then, in increasing cost, add only what the change needs:

| Check | Catches | Notes |
| --- | --- | --- |
| jsdom smoke (`scripts/smoke.mjs`) | runtime errors typecheck/build cannot: Panda recipe assertions, bad component usage, an empty `#root` | import the built bundle from `dist/assets`, stub `matchMedia` / `ResizeObserver` / `localStorage`, assert first-run content |
| jsdom flow (`scripts/flow.mjs`) | multi-step state: add → banner resolves → connect → sign-in dialog | serve canned stateful `fetch` responses; jsdom cannot drive real dialogs |
| Playwright against Vite | real interaction, layout, focus traps, a11y | `channel: 'chrome'`; its own port; `fullyParallel: false` when a suite drives one window |
| Playwright against the app + real backend | persistence, auth, concurrency | `webServer` array (backend health URL + Vite), a fresh backend data dir per run, capped workers |

The jsdom smoke asserts what the first render must contain, e.g. the demo
company selected, the demo banner, seeded rows, and the nav items. Update those
assertions when first-run behavior changes — that file is a spec, not a
formality.

A visual change you did not look at is unverified. Say "built" not "works".

## 11. Spec conventions

App behavior is worth a spec when it involves session, demo data, onboarding, or
API wiring. Follow the repo's existing format:

- `docs/spec/<topic>-spec.md`: problem → goals / non-goals → an interview
  decisions table (question → decision) → architecture → exact contracts
  (error-code mapping, state machine, endpoint coverage with ✅ / ⚠️ / ❌) →
  verification → implementation status.
- `docs/findings/<topic>.md` for evidence and limits; the todo list owns
  outstanding work.
- Update the status section when the work lands; do not present proposals as
  implemented.

## 12. Checklist before calling it done

- [ ] `pnpm codegen` runs in `predev`/`prebuild`; `styled-system` is gitignored
- [ ] Panda `include` covers the app **and** the design system; parity settings match
- [ ] entry imports generated sheet → design system `styles.css` → app CSS
- [ ] theme attribute and storage key match the design system; inline pre-paint script present
- [ ] shell is `100dvh` with per-pane scrolling; no page-level scrollbar
- [ ] every request goes through the typed client; views branch on `code`, not `message`
- [ ] 401 → session expiry path; fetch failure → offline state, token kept
- [ ] optimistic mutations have a replay or rollback path (outbox or refetch)
- [ ] demo/fixture data is labelled wherever it is visible, and never persisted as user data
- [ ] disabled nav items say "Soon" and are not clickable
- [ ] keyboard paths: number-key views, `⌘K`, Escape on overlays, visible focus
- [ ] browser and Tauri both run the same UI; native-only features are gated
- [ ] `pnpm typecheck` and `pnpm build` pass; smoke (or e2e) updated for changed first-run behavior
