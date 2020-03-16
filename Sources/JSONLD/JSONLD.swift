//
//  JSONLD.swift
//  JSONLD
//
//  Created by GWilliams on 3/12/20.
//  Copyright © 2020 GWilliams. All rights reserved.
//

import Foundation

public enum JSONLDAPIError: Error {
    case colliding_keywords
    case context_overflow
    case cyclic_IRI_mapping
    case invalid_base_direction
    case invalid_base_IRI
    case invalid_container_mapping
    case invalid_context_entry
    case invalid_context_nullification
    case invalid_default_language
    case invalid_id_value
    case invalid_import_value
    case invalid_included_value
    case invalid_index_value
    case invalid_IRI_mapping
    case invalid_keyword_alias
    case invalid_language_map_value
    case invalid_language_mapping
    case invalid_language_tagged_string
    case invalid_language_tagged_value
    case invalid_local_context
    case invalid_nest_value
    case invalid_prefix_value
    case invalid_propagate_value
    case invalid_remote_context
    case invalid_reverse_property
    case invalid_reverse_property_map
    case invalid_reverse_property_value
    case invalid_reverse_value
    case invalid_set_or_list_object
    case invalid_term_definition
    case invalid_type_mapping
    case invalid_type_value
    case invalid_typed_value
    case invalid_value_object
    case invalid_value_object_value
    case invalid_version_value(JSON)
    case IRI_confused_with_prefix
    case keyword_redefinition
    case loading_remote_context_failed(Error?)
    case processing_mode_conflict
    case protected_term_redefinition
}

public enum JSONLDError: Error {
    case datatypeError(String)
    case missingValue
    case unimplemented_XXX
    case no_remote_context_support_XXX
}

private extension URLSession {
    func synchronousDataTask(with url: URL) -> (Data?, URLResponse?, Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?

        let semaphore = DispatchSemaphore(value: 0)

        let dataTask = self.dataTask(with: url) {
            data = $0
            response = $1
            error = $2

            semaphore.signal()
        }
        dataTask.resume()

        _ = semaphore.wait(timeout: .distantFuture)

        return (data, response, error)
    }
}

extension String {
    var looksLikeKeyword: Bool {
        if self.hasPrefix("@") { // /^@[A-Za-z]+$/
            let suffix = self.dropFirst()
            let keyword = suffix.allSatisfy { (c) -> Bool in
                guard let u = c.asciiValue else {
                    return false
                }
                let v = Int(u)
                let upper = 65...90
                let lower = 97...122
                return upper.contains(v) || lower.contains(v)
            }
            return keyword
        }
        return false
    }
}

extension Array {
    func anySatisfy(_ predicate: (Element) throws -> Bool) rethrows -> Bool {
        for v in self {
            if try predicate(v) {
                return true
            }
        }
        return false
    }
}

public class JSONLD {
    let JSONLDKeywords = Set([
        ":",
        "@base",
        "@container",
        "@context",
        "@direction",
        "@graph",
        "@id",
        "@import",
        "@included",
        "@index",
        "@json",
        "@language",
        "@list",
        "@nest",
        "@none",
        "@prefix",
        "@propagate",
        "@protected",
        "@reverse",
        "@set",
        "@type",
        "@value",
        "@version",
        "@vocab",
    ])
    
    struct TermDefinition: Equatable {
        var __source_base_iri: URL
        var protected: Bool
        var type_mapping: String?
        var iri_mapping: String?
        var language_mapping: String?
        var direction_mapping: TextDirection?
        var container_mapping: [String]
        var reverse: Bool
        var prefix_flag: Bool
        var nest_value: String?
        var context: JSON?
        var index_mapping: String?
        init(base: URL) {
            self.__source_base_iri = base
            self.protected = false
            self.type_mapping = nil
            self.iri_mapping = nil
            self.language_mapping = nil
            self.direction_mapping = nil
            self.container_mapping = []
            self.index_mapping = nil
            self.reverse = false
            self.prefix_flag = false
            self.context = nil
        }
        
        func equalsIgnoringProtected(_ other: TermDefinition) -> Bool {
            var a = self
            a.protected = false
            
            var b = other
            b.protected = false
            
            return a == b
        }
    }
    
    public class Context {
        var original_base_URL: URL
        var base: URL?
        var vocab: String? = nil
        var language: String? = nil
        var direction: TextDirection? = nil
        var terms: [String: TermDefinition] = [:]
        var previous_context: Context? = nil

        init(original_base_URL: URL, base: URL?) {
            self.original_base_URL = original_base_URL
            self.base = base
        }
        func definition(for term: String) -> TermDefinition? {
            return terms[term]
        }
        
        func clone() -> Context {
            let c = Context(original_base_URL: original_base_URL, base: base)
            c.vocab = vocab
            c.language = language
            c.direction = direction
            c.terms = terms
            c.previous_context = previous_context
            return c
        }
        
        var protectedTerms: Set<String> {
            var protected = Set<String>()
            for (k, defn) in terms {
                if defn.protected {
                    protected.insert(k)
                }
            }
            return protected
        }
        
        var containsProtectedTerms: Bool {
            return !protectedTerms.isEmpty
        }
        
        func addDefinition(_ defn: TermDefinition, forTerm term: String) {
            self.terms[term] = defn
        }
        
        func removeDefinition(forTerm term: String) {
            self.terms.removeValue(forKey: term)
        }
    }
    
    enum ProcessingMode {
        case json_ld_10
        case json_ld_11
    }
    
    enum TextDirection: String, Equatable {
        case rtl
        case ltr
        
        static func fromString(_ value: String) -> Self? {
            switch value {
            case "rtl":
                return .rtl
            case "ltr":
                return .ltr
            default:
                return nil
            }
        }
    }
    
    var base: URL
    var processingMode: ProcessingMode = .json_ld_11
    var defaultBaseDirection: TextDirection?
    var defaultLanguage: String?
    var parsedRemoteContexts: [URL: JSON]
    var maxRemoteContexts: Int = 10

    public init() {
        self.base = URL(string: "http://example.org/")!
        self.parsedRemoteContexts = [:]
    }
    
    func warning(_ e: String) {
        print("*** \(e)")
    }
    
    func apiError(_ e: JSONLDAPIError) throws -> Never {
        throw e
    }
    
    func error(_ e: JSONLDError) throws -> Never {
        throw e
    }
    
    func _is_iri(_ value: String?) -> Bool {
        guard let value = value else {
            return false
        }
        guard let _ = URL(string: value) else {
            return false
        }
        return true
    }
    
    func _is_absolute_iri(_ value: String) -> Bool {
        let base = URL(string: "http://base.example.org/")!
        guard let u = URL(string: value, relativeTo: base) else {
            return false
        }
        return (value == u.absoluteString)
    }
    
    func loadDocument(url: URL, profile: String, requestProfile: Set<String>) -> (Data?, URLResponse?, Error?) {
        let session = URLSession.shared
        return session.synchronousDataTask(with: url)
    }

    func newContext(base url: URL) -> Context {
        return Context(
            original_base_URL: url,
            base: url
        )
    }
    
    
}
