import Foundation

/// Display metadata for the voices the model ships with (from `gradium/phonon-voices`).
/// Names the catalog does not know still appear, under "Other".
nonisolated struct VoiceInfo: Identifiable, Hashable, Sendable {
    enum Gender: String, CaseIterable, Identifiable, Sendable {
        case female, male, character

        var id: Self { self }
        var title: String {
            switch self {
            case .female: "Female"
            case .male: "Male"
            case .character: "Characters"
            }
        }
    }

    /// The name the model uses, passed back to `setVoice`.
    let id: String
    let displayName: String
    let gender: Gender?
    let accent: String

    /// Two letters for the avatar.
    var initials: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters.isEmpty ? Array(displayName.prefix(1)) : letters).uppercased()
    }
}

nonisolated enum VoiceCatalog {
    private static let usFemale = ["Zoey", "Juniper", "Everly", "Harper", "Hadley", "Delia"]
    private static let usMale = ["Easton", "Micah", "Trevor", "Russell", "Preston", "Miles"]
    private static let ukFemale = ["Maeve", "Freya", "Pippa", "Elodie-Rose", "Imogen", "Lottie", "Bryony"]
    private static let ukMale = ["Alfie", "Hugh", "Edwin", "Spencer", "Toby", "Teddy"]
    private static let characters = [
        "Captain Silas Blackwater", "Morwenna of the Deep", "Old Mortlake", "Azgorath",
        "Fennick the Young Elf", "The Thing Under the Stairs", "Vyrmathrax the Ancient",
        "Grub the Ogre", "Master Aldric", "The Snow Queen", "Sir Bramwell", "Fairy Godmother",
    ]

    private static let known: [String: (String, VoiceInfo.Gender, String)] = {
        var table: [String: (String, VoiceInfo.Gender, String)] = [:]
        func add(_ names: [String], _ gender: VoiceInfo.Gender, _ accent: String) {
            for name in names { table[key(name)] = (name, gender, accent) }
        }
        add(usFemale, .female, "American")
        add(usMale, .male, "American")
        add(ukFemale, .female, "British")
        add(ukMale, .male, "British")
        add(characters, .character, "Character")
        return table
    }()

    /// Matches model names written as `Zoey`, `zoey`, `en_zoey`, `captain_silas_blackwater` and so on.
    private static func key(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter }
    }

    static func info(for name: String) -> VoiceInfo {
        if name == "default" {
            return VoiceInfo(id: name, displayName: "Default", gender: nil, accent: "Default")
        }
        let normalized = key(name)
        if let match = known[normalized] {
            return VoiceInfo(id: name, displayName: match.0, gender: match.1, accent: match.2)
        }
        // Language-prefixed names such as `en · Old Mortlake` or `en-gb · Alfie`.
        let prefixAccent = accent(fromPrefixOf: name)
        for (knownKey, match) in known where normalized.hasSuffix(knownKey) {
            let prefixLength = normalized.count - knownKey.count
            guard prefixLength <= 5 else { continue }
            return VoiceInfo(id: name, displayName: match.0, gender: match.1, accent: match.2)
        }
        return VoiceInfo(id: name, displayName: bareName(name), gender: nil, accent: prefixAccent ?? "Other")
    }

    /// The name without a leading language tag.
    private static func bareName(_ name: String) -> String {
        let separators: Set<Character> = ["·", "_", "/", ":"]
        let tail = name.split(whereSeparator: { separators.contains($0) }).last.map(String.init) ?? name
        let trimmed = tail.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    private static func accent(fromPrefixOf name: String) -> String? {
        let lower = name.lowercased()
        if lower.hasPrefix("en-gb") || lower.hasPrefix("en_gb") { return "British" }
        if lower.hasPrefix("en-us") || lower.hasPrefix("en_us") { return "American" }
        return nil
    }
}
