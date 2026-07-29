# Rift — website (Next.js)

Static Next.js site for Rift ("The Mastering Room" concept, see
[`../WEBSITE_BUILD_PROMPT.md`](../WEBSITE_BUILD_PROMPT.md)). Server components emit
full HTML (works with JS disabled); one client `Enhancements` component adds GSAP
motion, the bottom waveform scrubber, album-poster parallax, the scroll-pinned
`ScrollDeck`, pointer tilt, magnetic buttons, and live GitHub-release info.

## Develop
```bash
cd website
npm install
npm run dev        # http://localhost:3000
```

## Build (static export → GitHub Pages)
```bash
npm run build      # emits ./out (output: "export")
```
`out/` is plain static files — no server, no telemetry.

## Deploy
Serve `website/out/` on GitHub Pages. In CI (`GITHUB_ACTIONS=true`)
`next.config.mjs` sets `basePath`/`assetPrefix` to `/rift-music-app`; change the
`repo` const there for a different Pages path, or drop both for a custom domain.

## Structure
- `src/app/` — layout (fonts, theme script, metadata, JSON-LD, sitemap/robots), page (section order), `globals.css` (tokens + all styles)
- `src/components/` — `Chrome` (nav / bottom scrubber / footer), `Sections`, `ScrollDeck` (pinned scroll-swap), `Enhancements` (client motion), `icons`
- `src/lib/config.ts` — repo / release URLs
- `public/img/shots/` — the 7 real app screenshots

Fonts self-host at build via `next/font/google` (Fraunces + Space Grotesk) — no
runtime font CDN. Album-poster parallax uses gradient tiles; swap for real cover art
in `Enhancements.tsx` when available.
