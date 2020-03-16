//
//  main.swift
//  JSONLD
//
//  Created by GWilliams on 2/24/20.
//  Copyright © 2020 GWilliams. All rights reserved.
//

import Foundation
import JSONLD
import ArgumentParser

struct JSONLDExpand: ParsableCommand {
    @Argument()
    var inputFile: String

    func expand(_ input: Data) throws -> JSON {
        let api = JSONLD()
        guard let j = JSON.decode(input) else {
            throw JSONLDError.datatypeError("Failed to decode input data")
        }
        let e = try api.expand(data: j)
        return e
    }
    
    func run() throws {
        let url = URL(fileURLWithPath: inputFile)
        let input = try Data(contentsOf: url)
        do {
            let e = try self.expand(input)
            print(e.debugDescription)
        } catch let e {
            print(e)
        }
    }
    
    func test() {
        //let input = """
        //{"@id": "http://example.org/test#example", "http://example.org/prop": "http://example.org/type"}
        //""".data(using: .utf8)!

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
        """.data(using: .utf8)!

        let expected = """
        [{
          "@id": "http://example.com/id1",
          "@type": ["http://example.com/t1"],
          "http://example.com/term1": [{"@value": "v1"}],
          "http://example.com/term2": [{"@value": "v2", "@type": "http://example.com/t2"}],
          "http://example.com/term3": [{"@value": "v3", "@language": "en"}],
          "http://example.com/term4": [{"@value": 4}],
          "http://example.com/term5": [{"@value": 50}, {"@value": 51}]
        }]
        """.data(using: .utf8)!

        do {
            let e = try self.expand(input)
            print(e.debugDescription)
        } catch let e {
            print(e)
        }
    }
}

JSONLDExpand.main()
