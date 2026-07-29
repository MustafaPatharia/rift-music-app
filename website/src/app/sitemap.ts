import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const base = "https://mustafapatharia.github.io/rift-music-app";
  return [{ url: `${base}/`, changeFrequency: "monthly", priority: 1 }];
}
