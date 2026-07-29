/** @type {import('next').NextConfig} */
// Static export → GitHub Pages. No server runtime, no telemetry.
const isCI = process.env.GITHUB_ACTIONS === "true";
const repo = "rift-music-app"; // set to your Pages repo/subpath

const nextConfig = {
  output: "export",
  images: { unoptimized: true }, // required for static export
  basePath: isCI ? `/${repo}` : "",
  assetPrefix: isCI ? `/${repo}/` : "",
  trailingSlash: true,
  reactStrictMode: true,
};

export default nextConfig;
