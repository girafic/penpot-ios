import Foundation
import CoreText

/// Metadata extracted from a font file before uploading it. Penpot's backend never
/// opens the font — it stores `font-family`/`weight`/`style` verbatim (only format
/// conversion happens server-side), so the CLIENT must parse them, exactly like the
/// web app does in the browser. ttf/otf are read natively via CoreText; woff/woff2
/// (which CoreText can't open) fall back to filename heuristics — the same fallback
/// the web uses for woff2.
struct FontFileMetadata: Equatable {
    let family: String
    /// Penpot weight bucket: 100…900.
    let weight: Int
    /// `"normal"` or `"italic"`.
    let style: String
    /// The uploads-map key: `font/ttf`, `font/otf`, `font/woff`, `font/woff2`.
    let mimeType: String

    /// Human-readable variant summary, e.g. "Inter — Bold Italic".
    var summary: String {
        let weightName: String = switch weight {
        case 100: "Thin"
        case 200: "Extra Light"
        case 300: "Light"
        case 400: "Regular"
        case 500: "Medium"
        case 600: "Semibold"
        case 700: "Bold"
        case 800: "Extra Bold"
        case 900: "Black"
        default: "\(weight)"
        }
        let styleSuffix = style == "italic" ? " Italic" : ""
        return "\(family) — \(weightName)\(styleSuffix)"
    }

    // MARK: Sniffing

    /// Font container magic bytes: `00 01 00 00` or "true" → ttf, "OTTO" → otf,
    /// "wOFF" → woff, "wOF2" → woff2; anything else is rejected.
    static func sniffMimeType(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let magic = [UInt8](data.prefix(4))
        switch magic {
        case [0x00, 0x01, 0x00, 0x00], [0x74, 0x72, 0x75, 0x65]:
            return "font/ttf"
        case [0x4F, 0x54, 0x54, 0x4F]:
            return "font/otf"
        case [0x77, 0x4F, 0x46, 0x46]:
            return "font/woff"
        case [0x77, 0x4F, 0x46, 0x32]:
            return "font/woff2"
        default:
            return nil
        }
    }

    // MARK: Parsing

    /// nil when the data is not a supported font container.
    static func parse(data: Data, filename: String) -> FontFileMetadata? {
        guard let mimeType = sniffMimeType(data) else { return nil }
        if mimeType == "font/ttf" || mimeType == "font/otf" {
            if let parsed = parseWithCoreText(data: data, mimeType: mimeType) {
                return parsed
            }
        }
        // woff/woff2 — or a ttf/otf CoreText choked on: filename heuristics.
        return parseFromFilename(filename, mimeType: mimeType)
    }

    private static func parseWithCoreText(data: Data, mimeType: String) -> FontFileMetadata? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
              !family.isEmpty else { return nil }

        // The style/subfamily name wins over numeric traits (web parity: names like
        // "SemiBold" are authored intent; the trait float is derived and lossy).
        let styleName = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String ?? ""
        var weight = weight(fromName: styleName)
        var italic = isItalic(name: styleName)

        if let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] {
            if weight == nil, let value = traits[kCTFontWeightTrait] as? Double {
                weight = weightBucket(fromTrait: value)
            }
            if !italic, let symbolic = traits[kCTFontSymbolicTrait] as? UInt32 {
                italic = CTFontSymbolicTraits(rawValue: symbolic).contains(.traitItalic)
            }
        }

        return FontFileMetadata(family: sanitizedFamily(family),
                                weight: weight ?? 400,
                                style: italic ? "italic" : "normal",
                                mimeType: mimeType)
    }

    private static func parseFromFilename(_ filename: String, mimeType: String) -> FontFileMetadata? {
        let stem = (filename as NSString).deletingPathExtension
        let weight = weight(fromName: stem) ?? 400
        let italic = isItalic(name: stem)
        let family = sanitizedFamily(strippedFamilyName(from: stem))
        guard !family.isEmpty else { return nil }
        return FontFileMetadata(family: family, weight: weight,
                                style: italic ? "italic" : "normal", mimeType: mimeType)
    }

    /// Removes weight/style words and separators from a filename stem, leaving the
    /// family ("Inter-ExtraLight" → "Inter").
    static func strippedFamilyName(from stem: String) -> String {
        var name = stem
        let noise = ["extra light", "ultra light", "extralight", "ultralight",
                     "extra bold", "ultra bold", "extrabold", "ultrabold",
                     "semi bold", "demi bold", "semibold", "demibold",
                     "thin", "hairline", "light", "regular", "normal", "book", "medium",
                     "bold", "black", "heavy", "italic", "oblique", "variable"]
        for word in noise {
            name = name.replacingOccurrences(of: word, with: "", options: [.caseInsensitive])
        }
        name = name.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// The web's parse-font-weight word table (common/media.cljc).
    static func weight(fromName name: String) -> Int? {
        let lowered = name.lowercased()
        let table: [(String, Int)] = [
            ("thin", 100), ("hairline", 100),
            ("extra light", 200), ("extralight", 200), ("ultra light", 200), ("ultralight", 200),
            ("semi bold", 600), ("semibold", 600), ("demi bold", 600), ("demibold", 600),
            ("extra bold", 800), ("extrabold", 800), ("ultra bold", 800), ("ultrabold", 800),
            ("light", 300),
            ("regular", 400), ("normal", 400), ("book", 400),
            ("medium", 500),
            ("bold", 700),
            ("black", 900), ("heavy", 900),
        ]
        // Longest/most-specific first is encoded by table order ("semibold" before "bold").
        for (word, weight) in table where lowered.contains(word) {
            return weight
        }
        return nil
    }

    static func isItalic(name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("italic") || lowered.contains("oblique")
    }

    /// CoreText weight trait (−1…1) → Penpot bucket, split at the midpoints of
    /// UIFont.Weight's raw values.
    static func weightBucket(fromTrait value: Double) -> Int {
        switch value {
        case ..<(-0.60): 100
        case ..<(-0.44): 200
        case ..<(-0.20): 300
        case ..<0.11: 400
        case ..<0.26: 500
        case ..<0.35: 600
        case ..<0.48: 700
        case ..<0.59: 800
        default: 900
        }
    }

    /// Backend family constraint: letters/digits/space/`_.-`, max 250 chars — anything
    /// else would 400 with params-validation.
    static func sanitizedFamily(_ raw: String) -> String {
        let cleaned = raw.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || scalar == " " || scalar == "_" || scalar == "." || scalar == "-"
        }
        return String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespaces)
            .prefix(250)
            .trimmingCharacters(in: .whitespaces)
    }
}
