import XCTest
@testable import PortOS_Recall

final class AnalysisServiceTests: XCTestCase {

    func testAnalyzeWithKnownTranscript() async {
        let transcript = """
        We decided to move the launch date to April. John will update the roadmap by Friday. \
        Sarah agreed to handle the marketing materials. The team confirmed that we need to \
        increase the budget by twenty percent. Alice should follow up with the vendor about pricing.
        """

        let analysis = await AnalysisService.analyze(transcript: transcript)

        XCTAssertFalse(analysis.summary.isEmpty)
        XCTAssertFalse(analysis.actionItems.isEmpty, "Should extract action items")
        XCTAssertFalse(analysis.decisions.isEmpty, "Should extract decisions")
    }

    func testAnalyzeEmptyTranscript() async {
        let analysis = await AnalysisService.analyze(transcript: "")
        XCTAssertEqual(analysis.summary, "No content to summarize.")
    }

    func testActionItemExtraction() async {
        let transcript = "We will deploy on Monday. Bob should review the PR. The team needs to update docs."
        let analysis = await AnalysisService.analyze(transcript: transcript)
        XCTAssertGreaterThanOrEqual(analysis.actionItems.count, 2)
    }

    func testDecisionExtraction() async {
        let transcript = "The team decided to use Swift. We agreed on a two-week sprint cycle. Management confirmed the budget."
        let analysis = await AnalysisService.analyze(transcript: transcript)
        XCTAssertGreaterThanOrEqual(analysis.decisions.count, 2)
    }

    func testTopicExtraction() async {
        let transcript = """
        The database migration is critical for the project. We need to ensure the database \
        schema supports the new authentication system. The authentication tokens should be \
        stored securely in the database.
        """
        let analysis = await AnalysisService.analyze(transcript: transcript)
        XCTAssertFalse(analysis.topics.isEmpty)
    }
}
