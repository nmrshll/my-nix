---
schemaVersion: 1
name: product-website
description: >
  Builds or extends a product's web presence: one shared web design system
  package, one Astro site that carries both the landing page and the docs, and
  one showcase site that documents the design system. Use when a product needs
  a homepage, documentation, a component gallery, or when a new app must join
  an existing web workspace.
aliases: [landing-docs, product-docs, website-workspace, docs-site, marketing-site]
dependencies: [design-system-baton, ui-design-system]
validationHints:
  - workspace has libs/<design-system>, apps/<docs-web>, demos/<design-system-showcase>
  - every panda.config.ts shares prefix, hash, separator and scans the design-system source
  - docs navigation comes from one data module, not from hand-written links per page
trigger:
  providers: ['*']
  scope: system
disable_model_invocation: false
user_invocable: true
---

## Boundary

This skill covers a **product website**: landing page + docs + design system +
showcase, living in the product's own repository. It does not cover designing a
brand, writing product copy, or building the product UI itself — use
`design-system-baton`, `ui-design-system`, and `frontend-design-anti-slop` for
those.

Default assumption: a desktop/CLI/library product with a static marketing site
and docs. Static output, no server rendering requirement, no CMS.

The product's own web app — a Solid SPA at `apps/<product>-web` — is deliberately
out of scope. That is `product-web-app`. This one ends at the marketing and
documentation surface, even though the app consumes the same design system.

## 1. The moving pieces

Four things, four jobs — but the showcase is the only optional one. Do not
merge the rest.

| Piece | Path | Job |
| --- | --- | --- |
| Design system | `libs/web-design-system` | Tokens, Panda preset, headless primitives, styled components, `.astro` wrappers, icons, global styles |
| Showcase (optional) | `demos/design-system-showcase` | Every component and token in isolation, plus full-page replicas. The living documentation of the system |
| Docs + landing site | `apps/<product>-docs-web` | `/` landing page, `/docs/**` user and contributor guides, `/downloads`, `/roadmap` |

Naming that has worked: unscoped `web-design-system` for a single-product repo;
scoped (`@tally/design-system`, `@money-tracker/design-system`,
`@recipes-lofi/web-design-system`) when the repo holds more than one product or
the package must be distinguishable in scripts.

Why the showcase is separate from the docs: the docs explain the **product**;
the showcase explains the **system**. Mixing them makes the docs navigation
carry contributor-only depth, and makes the showcase's placeholder content look
like product claims.

## 2. Stack (do not re-litigate)

- **Astro** for every static site — landing, docs, showcase. Layouts
  (`.astro`) deduplicate header/footer/sidebar.
- **SolidJS**, never React. `@astrojs/solid-js`; `jsxFramework: 'solid'` in Panda.
- **Panda CSS** for styling: tokens + recipes + `css()` in components. No
  Tailwind, no CSS modules, no styled-components.
- **Ark UI** (`@ark-ui/solid`) for headless behavior: dialog, popover, menu,
  tabs, tooltip, checkbox, switch, accordion.
- **TypeScript** everywhere. Self-hosted variable fonts via `@fontsource-variable/*`
  — no font CDN.
- CSS-only motion, `prefers-reduced-motion` honoured; WCAG 2.1 AA as the floor.
- Dark-first theming (`data-theme` on `<html>`, `_light` condition).

If a task asks for a different stack, that is a decision to confirm with the
user, not a default.

## 3. Workspace wiring

```
product/
├── package.json                 # private, packageManager: pnpm@<pinned>
├── pnpm-workspace.yaml          # "libs/*", "demos/*", "apps/*"
├── pnpm-lock.yaml               # committed
├── flake.nix                    # nodejs + pnpm in the devShell
├── Cargo.toml                   # exclude the JS packages when a Rust workspace shares the root
├── libs/web-design-system/
├── demos/design-system-showcase/     # optional
└── apps/<product>-docs-web/
```

One docs app **per product**. A monorepo with two products gets
`apps/product1-docs-web` and `apps/product2-docs-web`, each with its own
`panda.config.ts`, `styled-system/` and `docs.ts`. Never make one site carry two
products' docs; the navigation model assumes a single product's audience.

- pnpm 10/11 blocks dependency build scripts: add `allowBuilds: { esbuild: true }`
  (and `"@parcel/watcher": true` when something needs it) in
  `pnpm-workspace.yaml`, not `package.json`.
- Root scripts are the workflow. Every site gets a `dev`, `build`, `preview`,
  `typecheck`, and its own e2e script, and `codegen` runs first:

```json
{
  "codegen": "pnpm --dir libs/web-design-system run codegen",
  "dev": "pnpm --dir apps/<product>-docs-web run dev",
  "dev:ds": "pnpm --dir demos/design-system-showcase run dev",
  "build:docs": "pnpm run codegen && pnpm --dir apps/<product>-docs-web run build",
  "preview:docs": "pnpm --dir apps/<product>-docs-web run preview",
  "typecheck": "pnpm --dir libs/web-design-system run typecheck && pnpm --dir apps/<product>-docs-web run typecheck"
}
```

- Each consuming app repeats the chain in its own `predev`/`prebuild`, because
  `styled-system/` is generated per project:

```json
"codegen": "pnpm --filter web-design-system run codegen && panda codegen && panda cssgen --outfile styled-system/styles.css",
"predev": "pnpm run codegen",
"prebuild": "pnpm run codegen"
```

- `.gitignore`: `node_modules/`, `.astro/`, `dist/`, `styled-system/`, `.panda/`,
  `playwright-report/`, `test-results/`.
- When the repo root is a Rust workspace, add the JS dirs to
  `[workspace] exclude` so `cargo check --workspace` is unaffected. Keep the
  desktop theme and the web tokens decoupled unless explicitly asked.

## 4. The design system package

Five layers, one direction of dependency:

```
tokens ─► Panda preset ─┬─► headless (Ark UI, unstyled behaviour + ARIA)
                        ├─► styled   (Panda recipes + Solid components)
                        └─► astro    (.astro wrappers, hydration policy)
```

```
libs/web-design-system/
├── package.json          # source-consumed: exports point at src/**
├── panda.config.ts
├── DESIGN.md             # tokens, layers, conventions, a11y, testing, known gaps
├── README.md             # entry points + usage snippet + dev commands
├── src/
│   ├── preset.ts         # definePreset: tokens, semanticTokens, textStyles, recipes, keyframes
│   ├── tokens/           # colors, semantic, typography, spacing, sizes, radii, shadows, motion
│   ├── styles/           # reset.css, base.css, fonts.css — wrapped in cascade layers
│   ├── components/headless/   # Ark UI barrel
│   ├── components/styled/     # primitives + marketing/ + product/ + layout
│   ├── recipes/
│   ├── icons/
│   └── lib/cn.ts
└── tests/                # vitest
```

Exports map (source, not built):

```json
{
  ".": "./src/index.ts",
  "./preset": "./src/preset.ts",
  "./components": "./src/components/styled/index.ts",
  "./headless": "./src/components/headless/index.ts",
  "./icons": "./src/icons/index.tsx",
  "./styles.css": "./src/styles/index.css",
  "./astro/*": "./src/components/styled/*"
}
```

Rules:

- Components consume **semantic** tokens (`fg.muted`, `surface.subtle`,
  `accent.text`, `border.hairline`), never raw palette values, so light mode is
  a token swap rather than a component rewrite.
- One component per file, PascalCase matching the export. Props extend the DOM
  props and use `splitProps` so rest-props pass through.
- Interactive primitives are `.tsx` with a sibling `.astro` wrapper; styling
  keys off Ark's `data-*` attributes (`&[data-state="open"]`).
- Wrap the reset/base sheet in `reset` / `base` cascade layers, or an unlayered
  reset silently beats every Panda utility.
- `DESIGN.md` in the package is the contract. Write it at the same time as the
  tokens, not after.

## 5. Panda class parity — the failure that has no error

The single most expensive bug in this pattern. Panda generates a
`styled-system` per project, so the design system and every consumer each run
codegen. If they disagree, components render **unstyled with no error**.

Every `panda.config.ts` in the workspace must keep identical:

- `prefix` (`undefined`), `hash: false`, `separator: '_'`, `minify: false`
- `jsxFramework: 'solid'`, `preflight: false`, `outdir: 'styled-system'`

And every consumer must scan the design system's source:

```ts
export default defineConfig({
  presets: [pandaPreset, preset],        // our preset after the base one
  preflight: false,
  include: [
    './src/**/*.{ts,tsx,astro}',
    '../../libs/web-design-system/src/**/*.{ts,tsx,astro}',
  ],
  outdir: 'styled-system',
  jsxFramework: 'solid',
  prefix: undefined,
  hash: false,
  separator: '_',
  minify: false,
})
```

Two consequences to respect:

- **Astro does not run `postcss.config` for Panda here.** Generate the sheet
  explicitly: `panda codegen && panda cssgen --outfile styled-system/styles.css`,
  and import `styled-system/styles.css` in the layout.
- **Import order matters**: generated Panda sheet first (it declares the layer
  order), then the design system's `styles.css`, then app-level CSS.
- `hash: false` makes class and variable names readable (`--colors-canvas`),
  which the hand-written base CSS relies on. Keep it.
- Alias `styled-system` to the app's own generated directory in
  `astro.config.mjs`, so the package's internal `styled-system/*` imports
  resolve against the consumer's codegen.

## 6. Astro + Solid hydration policy

Hydration is opt-in and per component. Never a blanket `client:load`.

| Component kind | Directive | Why |
| --- | --- | --- |
| Ark-based wrapper (dialog, popover, menu, tabs, tooltip) | `client:only="solid"` | Ark portals do not SSR cleanly |
| Simple stateful wrapper (theme toggle, checkbox, switch) | `client:visible` | Needs JS, but not during SSR |
| Marketing sections, mock product UI | none — pure `.astro` | Static markup, zero runtime |
| Above-the-fold nav/search that must work immediately | `client:load` | Only when genuinely required |

`client:only` wrappers cannot receive slot content — pass body text as a prop
(`body`, `description`, `title`) instead of `<slot />`. Document the directive
on each wrapper and in the showcase entry.

## 7. The docs + landing site

One Astro app per product carries both the landing page and the docs. They share
`Base` and the header/footer, but not layouts:

- `layouts/Base.astro` — `<head>`, stylesheet imports, theme-before-paint
  inline script, `<slot />`.
- `layouts/Docs.astro` — the docs chrome.
- Landing pages use `SiteHeader` + section components directly.

### Docs navigation is data

One module, one source of truth — tabs, left nav, previous/next, and the
"Edit this page" link all read from it:

```ts
// src/data/docs.ts
export const docGuides: DocGuide[] = [
  { heading: 'User guide', summary: '…', href: '/docs', sections: [
      { heading: 'Getting started', items: [
          { label: 'Overview', href: '/docs' },
          { label: 'Install and run', href: '/docs/install' },
      ] },
  ] },
  { heading: 'Contributor guide', summary: '…', href: '/docs/contributor', sections: [ … ] },
]
```

Helpers: `guideFor(pathname)`, `guideSections(pathname)` (active flags),
`guideItems(pathname)` (reading order), `pageNeighbours(pathname)`,
`pageSourceUrl(pathname)`. Adding a page = one `.astro` file plus one entry.

### IA rules

- **Every documentation route lives under `/docs`.** Pages outside the tree are
  product pages (`/`, `/downloads`, `/roadmap`), not docs.
- **Two guides, split by audience, not by topic**: "User guide" (install, use,
  configure, sync) and "Contributor guide" (architecture, data model, dev
  setup, contributing, license). A single guide may be a flat list; multi-section
  guides nest under `section.heading`.
- Docs pages are prose `.astro` files, not Markdown pipelines — it keeps the
  design system's components usable inline and avoids a content-collection layer
  nobody asked for.

### Docs layout

```astro
grid-template-columns: 1fr | 240px minmax(0,1fr) | 240px minmax(0,1fr) 180px
```

- Three columns at `xl`: `DocSidebar` (sticky), article, `DocTOC` (sticky).
- Below `lg` the header tabs are hidden, so render guide/page pills above the
  article instead.
- `Prose` wrapper owns typographic rhythm and caps measure at `68ch`; pass the
  page's `toc` array to the layout so the TOC ids match heading ids.
- `TableScroll` around wide reference tables (focusable scroll region).
- Skip link to `#content`, `aria-current="page"` on the active nav item, real
  previous/next `<a rel="prev|next">` pager, and an "Edit this page on GitHub"
  link derived from the route.
- Page props: `title`, `description`, `toc`.

### Landing page

Section rhythm, top to bottom (adapt names, keep the order):

1. Sticky `SiteHeader` (brand, 2–3 product links, docs, theme toggle, primary CTA)
2. `Hero` — eyebrow/announcement pill, one promise, subtitle, note, primary +
   secondary CTA, one product visual (screenshot that fades into the canvas,
   or a design-system replica of the UI)
3. 5–8 feature sections, each one user-facing claim + visual, alternating sides,
   separated by a hairline or a `SectionSeparator`
4. Integrations / extensions section
5. Roadmap teaser linking to `/roadmap`
6. Closing `CTASection`
7. `Footer` (product, resources, company; theme toggle; license line)

Copy rules learned the hard way:

- Sell what the person gets, never the stack. A "Built with GPUI, Rust, SQLite,
  Astro" logo cloud is an anti-pattern; the stack belongs in the contributor
  docs.
- Never put an announcement about the documentation above the product headline.
- Do not market the docs' own information architecture.
- Downloads and roadmap get their own top-level routes so every CTA can point at
  them; the landing page links, it does not host the grids.
- Mock product data lives **outside `src/`** (`data/landing.ts`). Panda scans
  every file under `src/` for style-shaped objects and will turn `{ title, status,
  meta }` records into declarations like `meta: round 1;`, breaking the CSS build.
- Interactive-looking mock UI uses `span`s, not `button`s: a row of controls that
  do nothing is a lie to keyboard and screen-reader users.

## 8. The showcase (optional)

An Astro app in `demos/` with the design-system package linked by
`workspace:*`. **Skip it for small products** — a design system that is still
one token file and a dozen primitives is documented well enough by `DESIGN.md`
plus the docs site. Add the showcase when the system has enough surface that
someone would otherwise have to read component source to see the states.

Routes that have earned their place:

| Route | Content |
| --- | --- |
| `/` | What the system is, layer diagram, install/usage snippet |
| `/foundations` | Tokens: palette, semantic roles, type scale, spacing, radii, shadows, motion |
| `/layout` | `Box`, `Stack`, `Grid`, `Container`, `Separator` |
| `/primitives` | Every styled primitive with variants, sizes, states |
| `/marketing` | Every marketing section rendered in isolation |
| `/product-ui` | Every mock product component + a composed board/chat/diff scene |
| `/replicas/*` | Full-page replicas of the reference product's page families |

Every gallery entry shows the rendered component, its import path, its layer
(`headless` / `styled` / `astro`), and its hydration directive. Placeholder copy
only — no real wordmark, logo, screenshot, customer name, or quote.

No Storybook. `DESIGN.md`, plus the showcase gallery when it exists, are the
documentation.

## 9. Build order

Match the order in the specs; it front-loads the risky integration.

1. **Spec first** — `docs/spec/<topic>-spec.md` with an interview-decisions
   table (question → decision), architecture, inventory, risks, and an
   implementation-status section that is updated when work lands.
2. **Vertical slice** — workspace wiring, flake, one token set, `Button` +
   `Dialog` + a minimal navbar, one vitest spec, one Playwright smoke test.
   Prove Astro + Solid + Ark + Panda end to end before scaling out.
3. **Foundations** — full token set (dark + light), reset/base/fonts, layout
   primitives, `DESIGN.md`.
4. **Primitives** — headless barrel, styled components, `.astro` wrappers,
   gallery entries.
5. **Mock product UI** — issue rows, boards, timeline, chat, code, diff.
6. **Marketing sections** — navbar through footer.
7. **Docs site** — landing page, then `/docs`, then `/downloads` and `/roadmap`.
8. **A11y + motion pass**, then **polish** (responsive, READMEs, screenshots).

## 10. Verification

Default: three commands, no test infrastructure required.

```sh
pnpm codegen                                # every Panda consumer regenerates
pnpm typecheck                              # tsc --noEmit + astro check
pnpm --dir apps/<product>-docs-web build    # static build must succeed
```

Those three are the gate for routine changes. Add the heavier suites when the
design system starts being reused or before a public launch — not on day one:

| Suite | When | Covers |
| --- | --- | --- |
| Vitest in the package | Once tokens and recipes are stable | `cn`, token integrity, WCAG contrast math, one component render |
| Playwright against the showcase | Once the showcase exists | Every route loads, no console errors, the token sheet applies, theme toggle persists, axe finds no serious/critical WCAG 2.1 AA violations |
| Playwright against the docs site | Before publishing | Routes, docs nav and pager, mobile pills, `390px` no horizontal overflow, axe AA |

Playwright config conventions when you do add it:

- `channel: 'chrome'` — use the installed browser, no `playwright install`.
- One port per site (`4321` showcase, `4322` docs) so both suites can run at once.
- `webServer` runs `pnpm build && pnpm preview` so tests exercise real static output.
- `reuseExistingServer: !process.env.CI`.

Report compiled-only work as compiled, not tested. Visual changes you have not
looked at are unverified.

## 11. Deployment

The build output is a static `dist/`. The default is: **build, then copy `dist/`
to any static host.** Nothing in the site needs a server, database, or secret, so
hosting is a hosting decision, not an architecture one.

Provider variants, when the user names one:

| Host | How |
| --- | --- |
| Any static host | `pnpm build:docs`, then upload `apps/<product>-docs-web/dist` |
| Netlify | Git integration, or `netlify deploy --prod --dir=<dist>` |
| Render | Static site service: build `pnpm install && pnpm build:docs`, publish the same `dist` |
| Cloudflare Pages | Git integration, or `wrangler pages deploy <dist> --project-name <name>` |

Do not commit a `render.yaml`, `netlify.toml`, `vercel.json` or `wrangler.toml`
unless the user asks for that provider; the build is host-agnostic and no repo in
this workspace carries one. Build locally ≠ deploy: publishing needs explicit
user authorization.

## 12. Checklist before calling it done

- [ ] `pnpm codegen` clean in every package that runs Panda
- [ ] `prefix` / `hash` / `separator` / `minify` identical in every `panda.config.ts`
- [ ] every consumer's `include` scans `libs/web-design-system/src/**`
- [ ] generated sheet imported before the design system's `styles.css`
- [ ] no `client:load` on marketing sections; `client:only` wrappers take props, not slots
- [ ] new docs page appears in `src/data/docs.ts`, with `title`, `description`, `toc`
- [ ] mock data outside `src/`
- [ ] `DESIGN.md` and the package `README.md` updated with any new layer or token
- [ ] `pnpm typecheck` and the static build pass
- [ ] if e2e exists: axe AA passes on touched routes; 390px has no horizontal overflow; wide tables scroll inside their own region
- [ ] showcase omitted only for a small system, with the reason stated in the README
