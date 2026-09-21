//
//  SiteIndex.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// Websites people open by name. Anything with a dot in it is treated as a domain; everything
/// else must be in this list, or it is not a site.
public enum SiteIndex {
    public static let sites: [String: String] = [
        "youtube": "https://www.youtube.com", "you tube": "https://www.youtube.com",
        "gmail": "https://mail.google.com", "google mail": "https://mail.google.com",
        "google": "https://www.google.com", "google docs": "https://docs.google.com",
        "google drive": "https://drive.google.com", "drive": "https://drive.google.com",
        "google calendar": "https://calendar.google.com", "google sheets": "https://sheets.google.com",
        "google meet": "https://meet.google.com", "meet": "https://meet.google.com",
        "google maps": "https://maps.google.com",
        "github": "https://github.com", "git hub": "https://github.com",
        "twitter": "https://x.com", "x": "https://x.com",
        "reddit": "https://www.reddit.com", "instagram": "https://www.instagram.com",
        "facebook": "https://www.facebook.com", "linkedin": "https://www.linkedin.com", "linked in": "https://www.linkedin.com",
        "netflix": "https://www.netflix.com", "amazon": "https://www.amazon.com", "prime video": "https://www.primevideo.com",
        "chatgpt": "https://chatgpt.com", "chat gpt": "https://chatgpt.com", "claude": "https://claude.ai",
        "gemini": "https://gemini.google.com", "perplexity": "https://www.perplexity.ai",
        "notion": "https://www.notion.so", "linear": "https://linear.app", "figma": "https://www.figma.com",
        "slack": "https://app.slack.com", "discord": "https://discord.com/app",
        "stack overflow": "https://stackoverflow.com", "stackoverflow": "https://stackoverflow.com",
        "wikipedia": "https://www.wikipedia.org", "hacker news": "https://news.ycombinator.com",
        "twitch": "https://www.twitch.tv", "spotify web": "https://open.spotify.com",
        "vercel": "https://vercel.com", "supabase": "https://supabase.com", "aws": "https://console.aws.amazon.com",
        "apple": "https://www.apple.com", "icloud": "https://www.icloud.com",
        "whatsapp web": "https://web.whatsapp.com", "telegram web": "https://web.telegram.org",
        "canva": "https://www.canva.com", "leetcode": "https://leetcode.com", "lead code": "https://leetcode.com",
        "coursera": "https://www.coursera.org", "udemy": "https://www.udemy.com",
        "pinterest": "https://www.pinterest.com", "tiktok": "https://www.tiktok.com", "tik tok": "https://www.tiktok.com",
        "medium": "https://medium.com", "substack": "https://substack.com", "dribbble": "https://dribbble.com",
        "typesafe": "https://docs.typesafe.ai", "anthropic": "https://www.anthropic.com",
    ]

    private static let tlds = ["com", "org", "net", "io", "ai", "dev", "app", "co", "in", "me", "so", "tv", "gg", "xyz", "edu", "gov", "ly", "sh", "to", "us", "uk"]

    /// The URL a spoken site name means, or nil when it is not a site.
    public static func url(for spoken: String) -> URL? {
        var text = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["the ", "website ", "site "] where text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        for suffix in [" website", " site", " dot com", " dotcom", ".com"] where text.hasSuffix(suffix) {
            if suffix == " dot com" || suffix == " dotcom" || suffix == ".com" {
                text = String(text.dropLast(suffix.count)).replacingOccurrences(of: " ", with: "") + ".com"
            } else {
                text = String(text.dropLast(suffix.count))
            }
        }
        if let known = sites[text] { return URL(string: known) }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        // "github dot com slash ishan" -> github.com/ishan
        text = text.replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " slash ", with: "/")
        let host = text.split(separator: "/").first.map(String.init) ?? text
        let parts = host.split(separator: ".").map(String.init)
        if parts.count >= 2, let tld = parts.last, tlds.contains(tld), !host.contains(" ") {
            return URL(string: "https://" + text)
        }
        // A close call on a known site ("you tubes").
        var best: (String, Double)?
        for name in sites.keys {
            let s = Fuzzy.score(text, name)
            if s > (best?.1 ?? 0) { best = (name, s) }
        }
        if let best, best.1 >= 0.9, let known = sites[best.0] { return URL(string: known) }
        return nil
    }

    /// Whether the spoken words name a website with reasonable confidence.
    public static func confidence(for spoken: String) -> Double {
        url(for: spoken) == nil ? 0 : 1
    }
}
