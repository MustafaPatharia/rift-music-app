// Prefix a path in /public with the deployment's basePath.
//
// Next applies basePath to <Link> and to its own /_next assets, but NOT to a
// path we hand it verbatim: an unoptimized <Image src="/img/…"> and the
// metadata icons emit exactly what they're given. On GitHub Pages the site is
// served from /rift-music-app/, so those requests hit the domain root and 404
// — which is why every screenshot rendered as a broken image.
//
// NEXT_PUBLIC_BASE_PATH is set from basePath in next.config.mjs, so there is
// one source of truth and a local build (empty basePath) still works.
export const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function asset(path: string): string {
  return `${BASE_PATH}${path.startsWith("/") ? path : `/${path}`}`;
}
