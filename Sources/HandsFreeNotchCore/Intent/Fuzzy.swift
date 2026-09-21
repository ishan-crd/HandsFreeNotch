//
//  Fuzzy.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// Cheap string similarity for matching what speech recognition heard against names we know.
/// Speech errors are mostly split or merged words ("spot if I" for "spotify") and near
/// homophones, so both the spaced and the squashed forms are compared.
public enum Fuzzy {
    /// 0...1, where 1 is an exact match.
    public static func score(_ query: String, _ candidate: String) -> Double {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let c = candidate.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty || c.isEmpty { return 0 }
        if q == c { return 1 }

        let qs = squash(q)
        let cs = squash(c)
        if qs == cs { return 0.98 }
        if cs.hasPrefix(qs), qs.count >= 3 { return 0.9 + 0.05 * Double(qs.count) / Double(cs.count) }

        // Every query word is a prefix of some candidate word, in order: "visual code" ~ "visual studio code".
        let qWords = q.split(separator: " ").map(String.init)
        let cWords = c.split(separator: " ").map(String.init)
        if qWords.count > 1 || cWords.count > 1 {
            var i = 0
            var matched = 0
            for qw in qWords {
                while i < cWords.count, !cWords[i].hasPrefix(qw) { i += 1 }
                if i < cWords.count { matched += 1; i += 1 }
            }
            if matched == qWords.count, qWords.count >= 1 {
                return 0.85 + 0.1 * Double(qWords.count) / Double(max(cWords.count, 1))
            }
        }

        if cs.contains(qs), qs.count >= 4 { return 0.8 }

        let distance = levenshtein(qs, cs)
        let longest = max(qs.count, cs.count)
        // One wrong letter in a real word is a recognizer slip, not a different name.
        if distance <= 1, longest >= 5 { return 0.95 }
        return 1 - Double(distance) / Double(longest)
    }

    /// Letters and digits only, so "vs code", "vscode" and "v.s. code" all agree.
    public static func squash(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a.utf16), b = Array(b.utf16)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
