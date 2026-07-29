/** @type {import('next').NextConfig} */
// Static export → GitHub Pages. No server runtime, no telemetry.
const isCI = process.env.GITHUB_ACTIONS === "true";
const repo = "rift-music-app"; // set to your Pages repo/subpath
const basePath = isCI ? `/${repo}` : "";

const nextConfig = {
  output: "export",
  images: { unoptimized: true }, // required for static export
  basePath,
  assetPrefix: isCI ? `/${repo}/` : "",
  // basePath does NOT reach files we reference by absolute path ourselves —
  // an unoptimized <Image src="/img/…"> and the metadata favicon both emit the
  // path verbatim, which 404s under a repo subpath. Export it so `asset()`
  // (src/lib/asset.ts) can prefix them from the same single source of truth.
  env: { NEXT_PUBLIC_BASE_PATH: basePath },
  trailingSlash: true,
  reactStrictMode: true,
};

export default nextConfig;
