// SPDX-License-Identifier: GPL-3.0-only
//
// WikipediaClient — artist bio fallback. YTM's artist browse often carries no
// description (especially for smaller artists); Wikipedia's public REST API
// fills the About section. Two calls: title search → page summary.

import Foundation

enum WikipediaClient {

    /// Bio must clearly be about a music act, or we show nothing — a wrong or
    /// generic page (e.g. the "Justh is a surname" disambiguation) is worse
    /// than no About at all.
    private static let musicWords = [
        "singer", "musician", "rapper", "band", "songwriter", "composer",
        "music", "vocalist", "dj", "record producer", "playback",
    ]

    /// Short bio for an artist name, or nil. Guards:
    /// 1. hit title must contain the artist name (no "Dino (American singer)"
    ///    for "Dino James"),
    /// 2. page type must be "standard" (rejects disambiguation/surname pages),
    /// 3. the extract must mention music (singer/band/rapper/…).
    static func artistBio(named name: String) async -> String? {
        guard let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://en.wikipedia.org/w/rest.php/v1/search/title?q=\(q)&limit=5")
        else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: searchURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pages = json["pages"] as? [[String: Any]] else { return nil }
            let lowered = name.lowercased()
            // Exact title or "Name (rapper)" style only — a plain substring
            // match let "Justh" claim "Justhis", a different artist.
            let candidates = pages.compactMap { $0["title"] as? String }.filter { t in
                let tl = t.lowercased()
                return tl == lowered || tl.hasPrefix(lowered + " (")
            }

            for title in candidates {
                guard let t = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let summaryURL = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(t)")
                else { continue }
                let (sdata, _) = try await URLSession.shared.data(from: summaryURL)
                guard let sjson = try JSONSerialization.jsonObject(with: sdata) as? [String: Any],
                      (sjson["type"] as? String) == "standard",
                      let extract = sjson["extract"] as? String, !extract.isEmpty
                else { continue }
                let el = extract.lowercased()
                guard musicWords.contains(where: { el.contains($0) }) else { continue }
                return extract
            }
            return nil
        } catch { return nil }
    }
}
