//
//  Normalizer.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// Turns a raw speech transcript into the plain lowercase words the router matches on.
public enum Normalizer {
    private static let fillers: [String] = [
        "hey", "hi", "ok", "okay", "please", "can you", "could you", "would you", "will you",
        "i want to", "i want you to", "i need you to", "i'd like to", "i would like to", "let's", "lets",
        "um", "uh", "just", "computer", "mac", "notch",
    ]

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100,
        "to": 2, "too": 2, "for": 4,
    ]

    /// Lowercase, no punctuation, single spaces, leading and trailing fillers removed.
    public static func normalize(_ raw: String) -> String {
        var text = raw.lowercased()
        text = text.replacingOccurrences(of: "’", with: "'")
        text = text.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "'" || scalar == "." || scalar == "-" || scalar == "/" || scalar == ":" {
                return String(scalar)
            }
            return " "
        }.joined()
        text = text.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        // A trailing full stop is punctuation; an inner one ("github.com") is part of a domain.
        while text.hasSuffix(".") { text.removeLast() }

        var changed = true
        while changed {
            changed = false
            for filler in fillers {
                if text == filler {
                    return ""
                }
                if text.hasPrefix(filler + " ") {
                    text = String(text.dropFirst(filler.count + 1))
                    changed = true
                }
                if text.hasSuffix(" " + filler) {
                    text = String(text.dropLast(filler.count + 1))
                    changed = true
                }
            }
        }
        return text
    }

    /// Splits "open spotify then play music" into its two commands. Only explicit sequencing
    /// words split; a bare "and" is left alone because it is often part of a name or a query.
    public static func splitSequence(_ text: String) -> [String] {
        let separators = [" and then ", " then ", " after that ", " and also ", " also "]
        var parts = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// "three" -> 3, "3" -> 3, "a couple" -> 2, nil when the word is not a count.
    public static func number(from word: String) -> Int? {
        if let n = Int(word) { return n }
        if word == "a" || word == "an" || word == "once" { return 1 }
        if word == "couple" || word == "twice" { return 2 }
        if word == "few" || word == "several" { return 3 }
        return numberWords[word]
    }

    /// The first number in the text, e.g. "set volume to 40 percent" -> 40.
    public static func firstNumber(in text: String) -> Int? {
        for word in text.split(separator: " ") {
            let w = String(word).replacingOccurrences(of: "%", with: "")
            if let n = Int(w) { return n }
            if let n = numberWords[w], w != "to", w != "too", w != "for" { return n }
        }
        return nil
    }
}
