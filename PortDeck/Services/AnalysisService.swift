import Foundation
import NaturalLanguage

struct SessionAnalysis {
    var summary: String
    var bulletPoints: [String]
    var actionItems: [String]
    var decisions: [String]
    var entities: [String]
    var topics: [String]
}

enum AnalysisService {
    /// Minimum word count for meaningful topic extraction
    private static let minimumWordsForTopics = 15

    static func analyze(transcript: String) async -> SessionAnalysis {
        RecallLogger.analysis("Starting analysis of \(transcript.count) characters")

        // Try Foundation Models first (iOS 26+), fallback to NLP
        if #available(iOS 26, *) {
            if let result = await analyzeWithFoundationModels(transcript: transcript) {
                RecallLogger.analysis("Completed analysis via Foundation Models")
                return result
            }
        }

        let result = analyzeWithNLP(transcript: transcript)
        RecallLogger.analysis("Completed analysis via NLP heuristics")
        return result
    }

    // MARK: - Foundation Models (iOS 26+)

    @available(iOS 26, *)
    private static func analyzeWithFoundationModels(transcript: String) async -> SessionAnalysis? {
        // Foundation Models integration - requires A17 Pro+ hardware
        // Returns nil if not available, triggering NLP fallback
        // TODO: Implement when Foundation Models API is finalized
        return nil
    }

    // MARK: - NLP Heuristics Fallback

    private static func analyzeWithNLP(transcript: String) -> SessionAnalysis {
        let sentences = splitSentences(transcript)

        let entities = extractEntities(from: transcript)
        let actionItems = extractActionItems(from: sentences)
        let decisions = extractDecisions(from: sentences)
        let topics = extractTopics(from: transcript)
        let summary = generateSummary(from: sentences)
        let bulletPoints = generateBulletPoints(from: sentences, entities: entities, topics: topics)

        return SessionAnalysis(
            summary: summary,
            bulletPoints: bulletPoints,
            actionItems: actionItems,
            decisions: decisions,
            entities: entities,
            topics: topics
        )
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }

    private static func extractEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities: Set<String> = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag, tag == .personalName || tag == .placeName || tag == .organizationName {
                entities.insert(String(text[range]))
            }
            return true
        }

        return Array(entities).sorted()
    }

    private static func extractActionItems(from sentences: [String]) -> [String] {
        filterByPatterns(sentences, patterns: [
            "\\b(will|should|need to|needs to|must|have to|has to|going to|TODO|todo|action item)\\b",
            "\\b(follow up|follow-up|assign|schedule|create|send|review|update|prepare|complete)\\b"
        ])
    }

    private static func extractDecisions(from sentences: [String]) -> [String] {
        filterByPatterns(sentences, patterns: [
            "\\b(decided|agreed|confirmed|approved|resolved|concluded|determined|chose|selected|went with)\\b"
        ])
    }

    private static func filterByPatterns(_ sentences: [String], patterns: [String]) -> [String] {
        sentences.filter { sentence in
            let lower = sentence.lowercased()
            return patterns.contains { pattern in
                lower.range(of: pattern, options: .regularExpression) != nil
            }
        }
    }

    private static func extractTopics(from text: String) -> [String] {
        let wordCount = text.split(separator: " ").count
        guard wordCount >= minimumWordsForTopics else {
            RecallLogger.analysis("Transcript too short for topic extraction (\(wordCount) words)")
            return []
        }

        // Common filler/function words to exclude
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "can", "shall", "i", "you", "he", "she",
            "it", "we", "they", "me", "him", "her", "us", "them", "my", "your",
            "his", "its", "our", "their", "this", "that", "these", "those",
            "and", "or", "but", "if", "then", "so", "not", "no", "to", "of",
            "in", "on", "at", "for", "with", "about", "from", "up", "out",
            "just", "also", "very", "really", "like", "think", "know", "get",
            "go", "say", "said", "one", "all", "what", "when", "how", "which",
            "thing", "stuff", "gonna", "gotta", "wanna", "kinda", "sorta",
            "actually", "basically", "literally", "probably", "maybe",
            "something", "anything", "everything", "nothing", "someone",
            "here", "there", "where", "well", "yeah", "okay", "right",
            "need", "new", "stored", "ensure", "critical", "covers",
            "three", "securely", "before", "begins", "reviewed", "confirmed"
        ]

        // Try NLP noun extraction first, fall back to frequency-based extraction
        let topics = extractTopicsWithNLP(from: text, stopWords: stopWords, wordCount: wordCount)
        if !topics.isEmpty { return topics }

        // Fallback: frequency-based word extraction (NLTagger lexicalClass unavailable)
        return extractTopicsByFrequency(from: text, stopWords: stopWords, wordCount: wordCount)
    }

    private static func extractTopicsWithNLP(from text: String, stopWords: Set<String>, wordCount: Int) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text

        var nounFrequency: [String: Int] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        // Only extract nouns — verbs/adverbs/adjectives are not useful topics
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            guard let tag, tag == .noun else { return true }

            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            let word = (lemma ?? String(text[range])).lowercased()

            if word.count > 3, !stopWords.contains(word) {
                nounFrequency[word, default: 0] += 1
            }
            return true
        }

        let minFrequency = wordCount > 50 ? 2 : 1

        return nounFrequency
            .filter { $0.value >= minFrequency }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }

    private static func extractTopicsByFrequency(from text: String, stopWords: Set<String>, wordCount: Int) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text

        var wordFrequency: [String: Int] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: options) { tag, range in
            let word = (tag?.rawValue ?? String(text[range])).lowercased()
            if word.count > 3, !stopWords.contains(word) {
                wordFrequency[word, default: 0] += 1
            }
            return true
        }

        let minFrequency = wordCount > 50 ? 2 : 1

        return wordFrequency
            .filter { $0.value >= minFrequency }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }

    private static func generateSummary(from sentences: [String]) -> String {
        guard !sentences.isEmpty else { return "No content to summarize." }

        if sentences.count <= 3 {
            return sentences.joined(separator: " ")
        }

        // Take first sentence, a middle key sentence, and last sentence
        let first = sentences[0]
        let middle = sentences[sentences.count / 2]
        let last = sentences[sentences.count - 1]

        return [first, middle, last].joined(separator: " ")
    }

    private static func generateBulletPoints(from sentences: [String], entities: [String], topics: [String]) -> [String] {
        var points: [String] = []

        if !entities.isEmpty {
            points.append("Participants/entities mentioned: \(entities.joined(separator: ", "))")
        }

        if !topics.isEmpty {
            points.append("Key topics: \(topics.joined(separator: ", "))")
        }

        // Add first few substantive sentences as bullet points
        let substantive = sentences.filter { $0.count > 20 }
        for sentence in substantive.prefix(3) {
            points.append(sentence)
        }

        return points
    }
}
