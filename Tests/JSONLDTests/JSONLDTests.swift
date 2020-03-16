import XCTest
@testable import JSONLD

final class JSONLDTests: XCTestCase {
    func expand(string: String) throws -> JSON {
        let data = string.data(using: .utf8)!
        let api = JSONLD()
        guard let j = JSON.decode(data) else {
            throw JSONLDError.datatypeError("Failed to decode input data")
        }
        return try api.expand(data: j)
    }
    
    func testSimpleExpansion() throws {
        let input = """
        {
          "@context": {
            "t1": "http://example.com/t1",
            "t2": "http://example.com/t2",
            "term1": "http://example.com/term1",
            "term2": "http://example.com/term2",
            "term3": "http://example.com/term3",
            "term4": "http://example.com/term4",
            "term5": "http://example.com/term5"
          },
          "@id": "http://example.com/id1",
          "@type": "t1",
          "term1": "v1",
          "term2": {"@value": "v2", "@type": "t2"},
          "term3": {"@value": "v3", "@language": "en"},
          "term4": 4,
          "term5": [50, 51]
        }
        """
        
        let got = try expand(string: input)
        let expected = JSON.decode("""
        [{
          "@id": "http://example.com/id1",
          "@type": ["http://example.com/t1"],
          "http://example.com/term1": [{"@value": "v1"}],
          "http://example.com/term2": [{"@value": "v2", "@type": "http://example.com/t2"}],
          "http://example.com/term3": [{"@value": "v3", "@language": "en"}],
          "http://example.com/term4": [{"@value": 4}],
          "http://example.com/term5": [{"@value": 50}, {"@value": 51}]
        }]
        """.data(using: .utf8)!)!
        
        XCTAssertEqual(got, expected)
    }

    static var allTests = [
        ("testSimpleExpansion", testSimpleExpansion),
    ]
}
