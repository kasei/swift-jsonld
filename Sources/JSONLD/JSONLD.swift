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

private extension String {
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

private extension Array {
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
    let keywords = Set([
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
    
    class Context {
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

    public func expand(data: JSON, expandContext: JSON? = nil) throws -> JSON {
        var ctx = newContext(base: self.base)
        if let expandContext = expandContext {
            var ec = expandContext
            if let _ec = ec["@context"] {
                ec = _ec
            }
            let base: URL
            if case .string(let s) = expandContext.value, let u = URL(string: s) {
                base = u
            } else {
                base = self.base
            }
            ctx = try self._4_1_2_ctx_processing(activeCtx: &ctx, localCtx: ec, base: base)
        }
        
        return try self._expand(activeCtx: &ctx, prop: nil, data: data)
    }
    
    func _expand(activeCtx: inout Context, prop: String?, data: JSON, frameExpansion: Bool = false, ordered: Bool = false, fromMap: Bool = false) throws -> JSON {
        var expandedOutput = try self._5_1_2_expansion(
            activeCtx: &activeCtx,
            activeProp: prop,
            element: data,
            frameExpansion: frameExpansion,
            ordered: ordered,
            fromMap: fromMap
        )
        if expandedOutput.is_map {
            let keys = expandedOutput.keys
            if keys == ["@graph"] {
                expandedOutput = expandedOutput["@graph"]!
            }
        }
        if !expandedOutput.defined {
            expandedOutput = JSON.wrap([])
        }
        
        expandedOutput = expandedOutput.as_array
        
        return expandedOutput
    }
    
    func newContext(base url: URL) -> Context {
        return Context(
            original_base_URL: url,
            base: url
        )
    }
    
    @discardableResult
    func _4_1_2_ctx_processing(activeCtx: inout Context, localCtx: JSON, base: URL? = nil, remoteContexts: [URL] = [], overrideProtected: Bool = false, propagate: Bool = true) throws -> Context {
        let base = base ?? self.base
        var propagate = propagate
        var localCtx = localCtx
        var result = activeCtx.clone()
        if localCtx.is_map && localCtx.has(key: "@propagate") {
            propagate = localCtx["@propagate", default: JSON.null].booleanValue
        }

        if !propagate && result.previous_context == nil {
            result.previous_context = activeCtx
        }
        
        localCtx = localCtx.as_array
        for context in localCtx.values_from_scalar_or_array {
            var context = context
            if !context.defined {
                // # 5.1
                if !overrideProtected && activeCtx.containsProtectedTerms {
                    try self.apiError(.invalid_context_nullification)
                } else {
                    let prev = result
                    result = Context(original_base_URL: self.base, base: self.base) // TODO: not sure this follows the spec, but it's what makes test t0089 pass
                    if propagate {
                        result.previous_context = prev
                    }
                    continue
                }
            }
            
            if let s = context.stringValue, let context_url = URL(string: s, relativeTo: base) {
                let contextString = context_url.absoluteString
                context = JSON.wrap(contextString)
                if remoteContexts.count > self.maxRemoteContexts {
                    try self.apiError(.context_overflow)
                }
                
                if let c = self.parsedRemoteContexts[context_url] {
                    context = c
                } else {
                    let (_data, resp, error) = try self.loadDocument(url: context_url, profile: "http://www.w3.org/ns/json-ld#context", requestProfile: ["http://www.w3.org/ns/json-ld#context"])
                    if let error = error {
                        try self.apiError(.loading_remote_context_failed(error))
                    }
                    guard let data = _data else {
                        try self.apiError(.loading_remote_context_failed(nil))
                    }
                    guard let j = JSON.decode(data), let context = j["@context"] else {
                        try self.apiError(.loading_remote_context_failed(nil))
                    }
                    self.parsedRemoteContexts[context_url] = context
                }

                result = try self._4_1_2_ctx_processing(activeCtx: &result, localCtx: context, base: context_url, remoteContexts: remoteContexts)
                continue
            }

            if !context.is_map {
                try self.apiError(.invalid_local_context)
            }

            if let v = context["@version"] {
                if v.doubleValue != 1.1 {
                    try self.apiError(.invalid_version_value(v))
                }
                if self.processingMode == .json_ld_10 {
                    try self.apiError(.processing_mode_conflict)
                }
            }

            if let value = context["@import"] {
                if self.processingMode == .json_ld_10 {
                    try self.apiError(.invalid_context_entry)
                }
                
                guard let valueString = value.stringValue else {
                    try self.apiError(.invalid_import_value)
                }

                guard let _import = URL(string: valueString, relativeTo: self.base) else {
                    try self.apiError(.loading_remote_context_failed(nil))
                }
//                try self.error(JSONLDError.no_remote_context_support_XXX)

                
                let (_data, resp, error) = try self.loadDocument(url: _import, profile: "http://www.w3.org/ns/json-ld#context", requestProfile: ["http://www.w3.org/ns/json-ld#context"])
                if let error = error {
                    try self.apiError(.loading_remote_context_failed(error))
                }
                guard let data = _data else {
                    try self.apiError(.loading_remote_context_failed(nil))
                }
                guard let j = JSON.decode(data), let import_context = j["@context"] else {
                    try self.apiError(.loading_remote_context_failed(nil))
                }
                
                if !import_context.is_map {
                    try self.apiError(.invalid_remote_context)
                }
                
                if import_context.has(key: "@import") {
                    try self.apiError(.invalid_context_entry)
                }
                
                for (k, v) in import_context.pairs {
                    context[k] = v
                }
//              %$context    = (%$import_context, %$context);
            }
            
            if let value = context["@base"], remoteContexts.isEmpty { // 5.7
                if !value.defined {
                    result.base = nil
                } else if let v = value.stringValue, self._is_absolute_iri(v) {
                    result.base = URL(string: v)
                } else if let base = result.base, let v = value.stringValue, self._is_absolute_iri(v) {
                    result.base = URL(string: v, relativeTo: base)
                } else {
                    try self.apiError(.invalid_base_IRI)
                }
            }

            if let value = context["@vocab"] { // 5.8
                if !value.defined {
                    result.vocab = nil
                } else if let v = value.stringValue, (v.hasPrefix("_") || self._is_iri(v)) {
                    let iri = try self._5_2_2_iri_expansion(activeCtx: &result, value: value, documentRelative: true, vocab: true)
                    result.vocab = iri.stringValue
                }
            }
            
            if let value = context["@language"] {
                if !value.defined {
                    result.language = nil
                } else if let l = value.stringValue {
                    result.language = l
//                  # TODO: validate language tag against BCP47
                } else {
                    try self.apiError(.invalid_default_language)
                }
            }
            
            if let value = context["@direction"] {
                if self.processingMode == .json_ld_10 {
                    try self.apiError(.invalid_context_entry)
                }

                if !value.defined {
                    result.direction = nil
                } else if let v = value.stringValue {
                    guard let d = TextDirection(rawValue: v) else {
                        try self.apiError(.invalid_base_direction)
                    }
                    result.direction = d
                }
            }

            if let p = context["@propagate"] {
                if self.processingMode == .json_ld_10 {
                    try self.apiError(.invalid_context_entry)
                }
                
                guard p.is_boolean else {
                    try self.apiError(.invalid_propagate_value)
                }
            }

            
            let defined = [String: Bool]()
            let skip = Set(["@base", "@direction", "@import", "@language", "@propagate", "@protected", "@version", "@vocab"])
            let keys = context.keys.filter { !skip.contains($0) }.sorted().reversed()
            for key in keys {
                let protected = context["@protected", default: JSON.null].booleanValue
                try self._4_2_2_create_term_definition(activeCtx: &result, localCtx: context, term: key, defined: defined, base: base, protected: protected, propagate: propagate)
            }
        }
        
        return result
    }
    
    let gen_delims = Set<Character>("[]:/?#@$")
    func _4_2_2_create_term_definition(activeCtx: inout Context, localCtx: JSON, term: String, defined: [String: Bool], base: URL? = nil, protected: Bool = false, overrideProtected: Bool = false, propagate: Bool = false) throws {
        var defined = defined
        if let d = defined[term] {
            if d {
                return
            } else {
                try self.apiError(.cyclic_IRI_mapping)
            }
        }

        defined[term] = false
        var value = localCtx[term, default: JSON.null] // clone
        //         # NOTE: the language interaction between 4 and 5 here is a mess. Unclear what "Otherwise" applies to. Similarly with the "Otherwise" that begins 7 below.
        if self.processingMode == .json_ld_11 && term == "@type" {
            if !value.is_map {
                try self.apiError(.keyword_redefinition)
            }
            let keys = value.keys.filter { $0 != "@protected" }
            if keys != ["@container"] {
                try self.apiError(.keyword_redefinition)
            }
            if value["@container"]?.stringValue != "@set" {
                try self.apiError(.keyword_redefinition)
            }
        } else {
            if keywords.contains(term) {
                try self.apiError(.keyword_redefinition)
            }
            if term.looksLikeKeyword {
                //                 warn "create term definition attempted on a term that looks like a keyword: $term\n";
                return
            }
        }
        
        let previousDefinition = activeCtx.definition(for: term)
        activeCtx.removeDefinition(forTerm: term)

        var simpleTerm = false
        if !value.defined {
            value = JSON.wrap(["@id": nil])
        } else if value.is_string {
            value = value.wrapped(withMapKey: "@id")
            simpleTerm = true
        } else if value.is_map {
            simpleTerm = false
        } else {
            try self.apiError(.invalid_term_definition)
        }

        var definition = TermDefinition(base: base ?? self.base)
        if value["@protected", default: JSON.null].booleanValue {
            definition.protected = true
        //             println "11 TODO processing mode of json-ld-1.0" if $debug;
        } else if !value.has(key: "@protected") && protected {
            definition.protected = true
        }
        
        if var type = value["@type"] {
            guard let typeString = type.stringValue else {
                try self.apiError(.invalid_type_mapping)
            }
            type = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: type, vocab: true, localCtx: localCtx, defined: defined)
            if (typeString == "@json" || typeString == "@none") && self.processingMode == .json_ld_10 {
                try self.apiError(.invalid_type_mapping)
            }
            
            if typeString != "@id" && typeString != "@vocab" && typeString != "@none" && typeString != "@json" && !self._is_absolute_iri(typeString) {
                try self.apiError(.invalid_type_mapping)
            }
            definition.type_mapping = typeString
        }
        
        if let reverse = value["@reverse"] { // 14
            if value.has(key: "@id") || value.has(key: "@nest") {
                try self.apiError(.invalid_reverse_property)
            }
            guard let reverseString = reverse.stringValue else {
                try self.apiError(.invalid_IRI_mapping)
            }

            if reverseString.looksLikeKeyword {
                self.warning("@reverse value looks like a keyword: \(reverseString)")
                return
            } else {
                let m = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: reverse, vocab: true, localCtx: localCtx, defined: defined)
                guard let s = m.stringValue, self._is_absolute_iri(s) else {
                    try self.apiError(.invalid_IRI_mapping)
                }
                definition.iri_mapping = s
            }
            
            if let c = value["@container"] {
                guard !c.defined || c.stringValue == "@set" || c.stringValue == "@index" else {
                    try self.apiError(.invalid_reverse_property)
                }
                
                if let s = c.stringValue {
                    definition.container_mapping = [s]
                } else {
                    definition.container_mapping = []
                }
            }
            
            definition.reverse = true
            activeCtx.addDefinition(definition, forTerm: term)
            defined[term] = true
            return
        }
        
        definition.reverse = false

        
        let termChars = Set(term)
        if let id = value["@id"], (!id.defined || id.stringValue != term) {
            if !id.defined {
                // 16.1
            } else {
                guard let idString = id.stringValue else {
                    try self.apiError(.invalid_IRI_mapping)
                }

                if id.defined && !keywords.contains(idString) && idString.looksLikeKeyword {
                    //                         warn "create term definition encountered an \@id that looks like a keyword: $id\n";
                    return
                } else {
                    let i = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: id, vocab: true, localCtx: localCtx, defined: defined)
                    guard let iri = i.stringValue else {
                        try self.error(.datatypeError("Expected string value from IRI expansion but got: \(i)"))
                    }
                    if !keywords.contains(iri) && !self._is_absolute_iri(iri) && !iri.contains(":") {
                        try self.apiError(.invalid_IRI_mapping)
                    }
                    if iri == "@context" {
                        try self.apiError(.invalid_keyword_alias)
                    }
                    definition.iri_mapping = iri
                }
                
                // testing term =~ /.:./
                var has_inner_colon = false
                if let i = term.firstIndex(of: ":"), i != term.startIndex {
                    has_inner_colon = true
                }
                if has_inner_colon || termChars.contains("/") {
                    // 16.2.4
                    defined[term] = true
                    let iri = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(term), vocab: true, localCtx: localCtx, defined: defined)
                    if iri.stringValue != definition.iri_mapping {
                        try self.apiError(.invalid_IRI_mapping)
                    }
                }
                
                let i = Set(definition.iri_mapping ?? "")
                let i_has_gen_delim = !i.intersection(gen_delims).isEmpty
                if !termChars.contains(":") && !termChars.contains("/") && simpleTerm && i_has_gen_delim {
                    definition.prefix_flag = true
                }
            }
        } else if termChars.contains(":") && term.lastIndex(of: ":") != term.startIndex {
            let pair = term.split(separator: ":", maxSplits: 1)
            let prefix = String(pair[0])
            let suffix = String(pair[1])
            if localCtx.has(key: prefix) {
                try self._4_2_2_create_term_definition(activeCtx: &activeCtx, localCtx: localCtx, term: prefix, defined: defined)
            }
            if let defn = activeCtx.definition(for: prefix) {
                definition.iri_mapping = (defn.iri_mapping ?? "") + suffix
            } else {
                definition.iri_mapping = term
            }
        } else if termChars.contains("/") {
            let i = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(term), vocab: true)
            definition.iri_mapping = i.stringValue
            if !self._is_iri(definition.iri_mapping) {
                try self.apiError(.invalid_IRI_mapping)
            }
        } else if term == "@type" {
            definition.iri_mapping = "@type"
        } else {
            // 20 ; NOTE: this section uses a passive voice "the IRI mapping of definition is set to ..." cf. 18 where it's active: "set the IRI mapping of definition to @type"
            if let v = activeCtx.vocab {
                definition.iri_mapping = v + term
            } else {
                try self.apiError(.invalid_IRI_mapping)
            }
        }

        
        if let container = value["@container"] { // 21
            let acceptable : Set<String?> = ["@graph", "@id", "@index", "@language", "@list", "@set", "@type"]
            if let s = container.stringValue, acceptable.contains(s) {
            } else if container.is_array {
                let acceptable2 : Set<String?> = ["@index", "@graph", "@id", "@type", "@language"]
                let values = container.values_from_scalar_or_array
                if values.count == 1 {
                    let c = container[0]
                    if !acceptable.contains(c?.stringValue) {
                        try self.apiError(.invalid_container_mapping)
                    }
                } else if values.anySatisfy({ $0.stringValue == "@id" || $0.stringValue == "@index" }) {
                } else if values.anySatisfy({ $0.stringValue == "@set" }) && values.anySatisfy({ acceptable2.contains($0.stringValue) }) {
                } else {
                    try self.apiError(.invalid_container_mapping)
                }
            } else {
                try self.apiError(.invalid_container_mapping)
            }

            if self.processingMode == .json_ld_10 {
                let acceptable : Set<String?> = ["@graph", "@id", "@type"]
                if acceptable.contains(container.stringValue) || !container.is_string {
                    try self.apiError(.invalid_term_definition)
                }
            }

            if container.is_array {
                definition.container_mapping = try container.values_from_scalar_or_array.map { (j) in
                    guard let s = j.stringValue else {
                        try self.error(.datatypeError("Expected container mapping to be array of strings, but got: \(container)"))
                    }
                    return s
                }
            } else {
                guard let s = container.stringValue else {
                    try self.error(.datatypeError("Expected container mapping to be a string, but got: \(container)"))
                }
                definition.container_mapping = [s]
            }
            
            if container.stringValue == "@type" {
                if definition.type_mapping == nil {
                    definition.type_mapping = "@id"
                }
                let tm = definition.type_mapping
                if tm != "@id" && tm != "@vocab" {
                    try self.apiError(.invalid_type_mapping)
                }
            }
        }
        
        if let index = value["@index"] { // 22
            let container_mapping = definition.container_mapping
            if self.processingMode == .json_ld_10 || !container_mapping.contains("@index") {
                try self.apiError(.invalid_term_definition)
            }
            let expanded = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: index)
            if !self._is_iri(expanded.stringValue) {
                try self.apiError(.invalid_term_definition)
            }
            definition.index_mapping = index.stringValue
        }
        
        if let context = value["@context"] {
            if self.processingMode == .json_ld_10 {
                try self.apiError(.invalid_term_definition)
            }
            try self._4_1_2_ctx_processing(activeCtx: &activeCtx, localCtx: context, base: base, overrideProtected: true)
            definition.context = context
        }

        if let language = value["@language"], !value.has(key: "@type") {
            // 24
            if !(!language.defined || language.is_string) {
                try self.apiError(.invalid_language_mapping)
            }
            //             # TODO: validate language tag against BCP47
            //             # TODO: normalize language tag
            definition.language_mapping = language.stringValue
        }
        
        if let direction = value["@direction"], !value.has(key: "@type") { // 25
            if !direction.defined {
            } else if direction.stringValue != "ltr" && direction.stringValue != "rtl" {
                try self.apiError(.invalid_base_direction)
            }
            
            if let s = direction.stringValue, let d = TextDirection(rawValue: s) {
                definition.direction_mapping = d
            } else {
                definition.direction_mapping = nil
            }
        }
        
        if let nv = value["@nest"] {
            if self.processingMode == .json_ld_10 {
                try self.apiError(.invalid_term_definition)
            }
            if !nv.defined || !nv.is_string {
                try self.apiError(.invalid_nest_value)
            } else if keywords.contains(nv.stringValue ?? "") && nv.stringValue != "@nest" {
                try self.apiError(.invalid_nest_value)
            }
            definition.nest_value = nv.stringValue
        }
        
        if let prefix = value["@prefix"] {
            if self.processingMode == .json_ld_10 || term.contains(":") || term.contains("/") {
                try self.apiError(.invalid_term_definition)
            }
            definition.prefix_flag = prefix.booleanValue
        //             # TODO: check if this value is a boolean. if it is NOT, die 'invalid @prefix value';
            
            if definition.prefix_flag && keywords.contains(definition.iri_mapping ?? "") {
                try self.apiError(.invalid_term_definition)
            }
        }
        
        let skip = Set(["@id", "@reverse", "@container", "@context", "@language", "@nest", "@prefix", "@type", "@direction", "@protected", "@index"])
        let keys = Set(value.keys).subtracting(skip)
        if !keys.isEmpty {
            print("invalid keys: \(keys)")
            try self.apiError(.invalid_term_definition)
        }
        
        if let prev = previousDefinition, !overrideProtected && prev.protected { // 29
            if !definition.equalsIgnoringProtected(prev) {
                try self.apiError(.protected_term_redefinition)
            }
            definition = prev
        }
        
        activeCtx.addDefinition(definition, forTerm: term)
        defined[term] = true
        return
    }
    
    func _5_1_2_expansion(activeCtx: inout Context, activeProp: String?, element: JSON, frameExpansion: Bool = false, ordered: Bool = false, fromMap: Bool = false) throws -> JSON {
        var frameExpansion = frameExpansion
        var activeCtx = activeCtx
        
        if !element.defined {
            return .null
        }
        
        if case .some("@default") = activeProp {
            frameExpansion = false
        }
        
        var propertyScopedCtx: JSON? = nil
        let tdef = activeProp.flatMap { activeCtx.definition(for: $0) }
        if let tdef = tdef, let lctx = tdef.context {
            propertyScopedCtx = lctx
        }

        if element.is_scalar {
            switch activeProp {
            case .none, .some("@graph"):
                return .null
            default:
                break
            }
            
            if let propertyScopedCtx = propertyScopedCtx {
                activeCtx = try self._4_1_2_ctx_processing(activeCtx: &activeCtx, localCtx: propertyScopedCtx)
            }
            
            let v = try self._5_3_2_value_expand(activeCtx: &activeCtx, activeProp: activeProp, value: element)
            return v
        }
        
        if element.is_array {
            var result = [JSON]()
            for item in element.values_from_scalar_or_array {
                var expandedItem = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: activeProp, element: item, fromMap: fromMap)
                let containerMapping = tdef?.container_mapping ?? []
                if containerMapping.contains("@list") && expandedItem.is_array {
                    expandedItem = expandedItem.wrapped(withMapKey: "@list")
                }
                
                if expandedItem.is_array {
                    result.append(contentsOf: expandedItem.values_from_scalar_or_array)
                } else if expandedItem.defined {
                    result.append(expandedItem)
                }
            }
            return JSON.wrap(result.map { $0.unwrap() })
        }
        
        if !element.is_map {
            try self.error(.datatypeError("Unexpected non-map encountered during expansion: \(element)"))
        }
        
        if let prevCtx = activeCtx.previous_context {
            if !fromMap {
                guard case .map(let dd) = element.value else {
                    try self.error(.datatypeError("Expected map but found \(element)"))
                }
                let keys = Array(dd.keys)
                let expandedKeys = try keys.map {
                    try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap($0), vocab: true)
                }
                let expandedKeyStrings = expandedKeys.compactMap { $0.stringValue }
                if !expandedKeyStrings.contains("@value") {
                    let key : JSON = keys.isEmpty ? .null : JSON.wrap(keys[0])
                    let i = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: key, vocab: true)
                    if !(keys.count == 1 && i.stringValue == "@id") {
                        activeCtx = prevCtx
                    }
                }
            }
        }
        
        if let propertyScopedCtx = propertyScopedCtx {
            activeCtx = try self._4_1_2_ctx_processing(activeCtx: &activeCtx, localCtx: propertyScopedCtx, base: tdef?.__source_base_iri, overrideProtected: true)
        }
        
        if let c = element["@context"] {
            activeCtx = try self._4_1_2_ctx_processing(activeCtx: &activeCtx, localCtx: c)
        }
        
        guard case .map(let dd) = element.value else {
            try self.error(.datatypeError("Expecting map but got \(element)"))
        }
        var typeScopedCtx = activeCtx.clone()
        for key in dd.keys.sorted() {
            var value = element[key]!
            let i = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(key), vocab: true)
            if i.stringValue != "@type" {
                continue
            }
            
            value = value.as_array
            
            let keys = value.values_from_scalar_or_array.compactMap { $0.stringValue }
            let tdefs = Dictionary(uniqueKeysWithValues: keys.map { ($0, typeScopedCtx.definition(for: $0)) })
            for term in value.values_from_scalar_or_array.compactMap({ $0.stringValue }).sorted() {
                guard let tdef = tdefs[term] else { continue }
                if let c = tdef?.context {
                    activeCtx = try self._4_1_2_ctx_processing(activeCtx: &activeCtx, localCtx: c, propagate: false)
                }
            }
        }
        
        // TODO: 12
        var result = JSON.wrap([:])
        var nests = [String: JSON]()
        var input_type = ""
        for key in element.keys {
            let expandedKey = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(key))
            if case .string("@type") = expandedKey.value {
                if let it = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: element[key]!).stringValue {
                    input_type = it
                }
            }
        }
        
//        print("Before 13: \(result.debugDescription)")
        try self._5_1_2_expansion_step_13(activeCtx: &activeCtx, typeScopedCtx: &typeScopedCtx, result: &result, activeProp: activeProp, inputType: input_type, nests: &nests, ordered: ordered, frameExpansion: frameExpansion, element: element)
//        print("After 13: \(result.debugDescription)")

        if result.has(key: "@value") {
            let keys = result.keys
            let acceptable = Set(["@direction", "@index", "@language", "@type", "@value"])
            for k in keys {
                if !acceptable.contains(k) {
                    try self.apiError(.invalid_value_object)
                }
            }
            
            if result.has(key: "@type") && (result.has(key: "@language") || result.has(key: "@direction")) {
                try self.apiError(.invalid_value_object)
            }

            let rv = result["@value"]
            if let tt = result["@type"], tt.stringValue == "@json" {
                // 15.2 no-op
            } else if !(rv?.defined ?? false) {
                // 15.3a
                return .null
            } else if let rv = rv, let rvv = rv["@value"], rvv.is_array && rvv.values_from_scalar_or_array.isEmpty {
                // 15.3b
                return .null
            } else if let rv = rv, rv.has(key: "@language") {
                try self.apiError(.invalid_language_tagged_value)
            } else if let rt = result["@type"], !self._is_iri(rt.stringValue) {
                try self.apiError(.invalid_typed_value)
            }
        } else if let rt = result["@type"], !rt.is_array {
            result["@type"] = rt.as_array
        } else if result.has(key: "@set") || result.has(key: "@list") {
            // 17
            let keys = result.keys.filter { $0 != "@set" && $0 != "@list" }
            if !keys.isEmpty {
                if keys == ["@index"] {
                    try self.apiError(.invalid_set_or_list_object)
                }
            }
            
            if let rs = result["@set"] {
                result = rs
            }
        }
        
        let keys = result.keys
        if result.is_map {
            if keys.count == 1 && keys[0] == "@language" {
                return .null
            }

            switch activeProp {
            case .none, .some("@graph"):
                if result.is_map && (keys.isEmpty || result.has(key: "@value") || result.has(key: "@list")) {
                    result = .null
                } else if result.is_map && keys.count == 1 && keys[0] == "@id" {
                    result = .null
                }
            default:
                break
            }
        }

        return result
    }

    func _5_1_2_expansion_step_13(activeCtx: inout Context, typeScopedCtx: inout Context, result: inout JSON, activeProp: String?, inputType: String, nests: inout [String: JSON], ordered: Bool, frameExpansion: Bool, element: JSON) throws {
        for (key, value) in element.pairs {
//            print("==============================")
//            print("[13, \(key)], value = \(value.debugDescription)")
//            print("\(result.debugDescription)")

            if key == "@context" {
                continue
            }
            
            let expandedProperty = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(key), vocab: true)
//            print("--------")
//            print("property -> \(expandedProperty)")
            
            let expandedPropertyString = expandedProperty.stringValue ?? ""
            if ((!expandedProperty.defined) || ((!expandedPropertyString.contains(":")) && !keywords.contains(expandedPropertyString))) {
                continue
            }

            var expandedValue: JSON = .null
            if keywords.contains(expandedPropertyString) {
                if activeProp == "@reverse" {
                    try self.apiError(.invalid_reverse_property_map)
                }
                if let epKey = expandedProperty.stringValue, let p = result[epKey] {
                    if expandedPropertyString != "@included" && expandedPropertyString != "@type" {
                        try self.apiError(.colliding_keywords)
                    }
                }
                
                if expandedPropertyString == "@id" {
                    if !value.is_string {
                        try self.apiError(.invalid_id_value)
                    } else {
                        expandedValue = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: value, documentRelative: true)
                    }
                }
                
                if expandedPropertyString == "@type" {
                    let is_string = value.is_string
                    let is_array = value.is_array
                    let is_array_of_strings = is_array && value.values_from_scalar_or_array.allSatisfy { $0.is_string }
                    if !is_string && !is_array_of_strings {
                        try self.apiError(.invalid_type_value)
                    }

                    if case .map(let dd) = value.value, dd.isEmpty {
                        expandedValue = value
                    } else if value.is_default_object {
                        let v = try self._5_2_2_iri_expansion(activeCtx: &typeScopedCtx, value: value, documentRelative: true, vocab: true)
                        expandedValue = v.wrapped(withMapKey: "@default")
                    } else {
                        if case .array(let list) = value.value {
                            let mapped = try list.map { try self._5_2_2_iri_expansion(activeCtx: &typeScopedCtx, value: $0, documentRelative: true, vocab: true) }
                            expandedValue = JSON.wrap(mapped.map { $0.unwrap() })
                        } else {
                            expandedValue   = try self._5_2_2_iri_expansion(activeCtx: &typeScopedCtx, value: value, documentRelative: true, vocab: true)
                        }
                    }
                    
                    if let t = result["@type"] {
                        var values = expandedValue.values_from_scalar_or_array
                        values.insert(t, at: 0)
                        expandedValue = JSON.wrap(values.map { $0.unwrap() })
                    }
                }
                
                if expandedPropertyString == "@graph" {
                    let v = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: "@graph", element: value, frameExpansion: frameExpansion, ordered: ordered)
                    if v.is_array {
                        expandedValue = v
                    } else {
                        expandedValue = v.as_array
                    }
                }


                if expandedPropertyString == "@included" {
                    if self.processingMode == .json_ld_10 {
                        continue
                    }
                    
                    expandedValue = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: activeProp, element: value, frameExpansion: frameExpansion, ordered: ordered)
                    if !expandedValue.is_array {
                        expandedValue = expandedValue.as_array
                    }
                    
                    for v in expandedValue.values_from_scalar_or_array {
                        if !v.is_node_object {
                            try self.apiError(.invalid_included_value)
                        }
                    }
                    
                    if let i = result["@included"] {
                        let values = i.values_from_scalar_or_array + expandedValue.values_from_scalar_or_array
                        expandedValue = JSON.wrap(values.map { $0.unwrap() })
                    }
                } else if expandedPropertyString == "@value" {
                    if inputType == "@json" {
                        expandedValue = value
                        if self.processingMode == .json_ld_10 {
                            try self.apiError(.invalid_value_object_value)
                        }
                    } else if !(value.is_scalar || !value.defined) {
                        try self.apiError(.invalid_value_object_value)
                    } else {
                        expandedValue = value
                    }
                    
                    if !expandedValue.defined {
                        result["@value"] = JSON.null
                        continue
                    }
                }

        //      # NOTE: again with the "Otherwise" that seems to apply to only half the conjunction
                if expandedPropertyString == "@language" {
                    if !value.is_string {
                        if frameExpansion {
                            //                  println "13.4.8.1 TODO: frameExpansion support"; # if $debug;
                        }
                        try self.apiError(.invalid_language_tagged_string)
                    }
                    expandedValue = value
        //          # TODO: validate language tag against BCP47
                }
                
                if expandedPropertyString == "@direction" {
                    if self.processingMode == .json_ld_10 {
                        continue
                    }
                    
                    if value.stringValue != "ltr" && value.stringValue != "rtl" {
                        try self.apiError(.invalid_base_direction)
                    }
                    
                    expandedValue = value
                    
                    if frameExpansion {
        //              println "13.4.9.4 TODO: frameExpansion support"; # if $debug;
                    }
                }
                
                if expandedPropertyString == "@index" {
                    if !value.is_string {
                        try self.apiError(.invalid_index_value)
                    }
                    expandedValue = value
                }
                
                if expandedPropertyString == "@list" {
                    if activeProp == nil || activeProp == "@graph" {
                        continue
                    }
                    
                    expandedValue = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: activeProp, element: value, frameExpansion: frameExpansion, ordered: ordered)
                    if !expandedValue.is_array {
                        expandedValue = expandedValue.as_array
                    }
                }
                
                if expandedPropertyString == "@set" {
                    expandedValue = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: activeProp, element: value, frameExpansion: frameExpansion, ordered: ordered)
                }
                
        //      # NOTE: the language here is really confusing. the first conditional in 13.4.13 is the conjunction "expanded property is @reverse and value is not a map".
        //      #       however, by context it seems that really everything under 13.4.13 assumes expanded property is @reverse, and the first branch is dependent only on 'value is not a map'.
                if expandedPropertyString == "@reverse" {
                    if !value.is_map {
                        try self.apiError(.invalid_reverse_value)
                    }
                    expandedValue = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: "@reverse", element: value, frameExpansion: frameExpansion, ordered: ordered) // # 13.4.13.1

                    
                    if let r = expandedValue["@reverse"], case .map(let rdd) = r.value {
                        for (property, item) in rdd {
                            let empty = JSON.wrap([])
                            let existing = result[property, default: empty]
                            let values = existing.values_from_scalar_or_array + item.values_from_scalar_or_array
                            result[property] = JSON.wrap(values.map { $0.unwrap() })
                      }
                  }
                    
                    if case .map(let dd) = expandedValue.value {
                        let keys = dd.keys.filter { $0 != "@reverse" }
                        if !keys.isEmpty {
                            var reverseMap : JSON
                            if let r = result["@reverse"] {
                                reverseMap = r
                            } else {
                                reverseMap = JSON.wrap([:])
                                result["@reverse"] = reverseMap
                            }
                            
                            for (property, items) in dd.filter({ $0.key != "@reverse" }) {
                                for item in items.values_from_scalar_or_array {
                                    if item.is_value_object || item.is_list_object {
                                        try self.apiError(.invalid_reverse_property_value)
                                    }
                                    
                                    let empty = JSON.wrap([])
                                    let values = reverseMap[property, default: empty].values_from_scalar_or_array + [item]
                                    reverseMap[property] = JSON.wrap(values.map { $0.unwrap() })
                                }
                            }
                            result["@reverse"] = reverseMap
                        }
                  }
                    continue // # 13.4.13.5
              }

                if expandedPropertyString == "@nest" {
                    nests[key] = nests[key, default: JSON.wrap([])]
                    continue
              }
                
                if frameExpansion {
                    let otherFramings = Set(["@explicit", "@default", "@embed", "@explicit", "@omitDefault", "@requireAll"])
                    if otherFramings.contains(expandedPropertyString) {
                        expandedValue = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: activeProp, element: value, frameExpansion: frameExpansion, ordered: ordered)
                    }
              }
        
                if !(!expandedValue.defined && expandedPropertyString == "@value" && inputType != "@json") {
                    result[expandedPropertyString] = expandedValue // # https://github.com/w3c/json-ld-api/issues/270
                }
                continue
            }

//            print("==============================")
//            print("[13, \(key)], value = \(value.debugDescription)")
//            print("\(result.debugDescription)")

            let tdef = activeCtx.definition(for: key)
            let containerMapping = tdef?.container_mapping ?? [] // # 13.5
            if let type_mapping = tdef?.type_mapping, type_mapping == "@json" {
                expandedValue = JSON.wrap(["@value": value.unwrap(), "@type": "@json"])
            } else if case .map(let dd) = value.value, containerMapping.contains("@language") {
                expandedValue = JSON.wrap([])
                var direction = activeCtx.direction
                if let dm = tdef?.direction_mapping {
                    direction = dm
                }
                
                for (language, languageValue) in dd.sorted(by: { $0.key <= $1.key }) {
                    for item in languageValue.values_from_scalar_or_array {
                        if !item.defined {
                            continue
                        }
                        
                        if !item.is_string {
                            try self.apiError(.invalid_language_map_value)
                        }
                        
                        var v = JSON.wrap([:])
                        v["@value"] = item
                        v["@language"] = JSON.wrap(language)
                        var wellFormed = true // # TODO: check BCP47 well-formedness of $item
                        if item.stringValue != "@none" && !wellFormed {
        //                  warn "Language tag is not well-formed: $item";
                        }
        //              # TODO: normalize language tag

                        let expandedLanguage = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(language))
                        if language == "@none" || expandedLanguage.stringValue == "@none" {
                            try v.removeValue(forKey: "@language")
                        }
                        
                        if let d = direction {
                            v["@direction"] = JSON.wrap(d.rawValue)
                        }
                        
                        expandedValue = expandedValue.appending(v)
                    }
                }
            } else if case .map(let dd) = value.value, containerMapping.contains(where: { Set(["@index", "@type", "@id"]).contains($0) }) {
                expandedValue = JSON.wrap([])
                let indexKey = tdef?.index_mapping ?? "@index"
                for (index, indexValue) in dd.sorted(by: { $0.key <= $1.key }) {
                    var indexValue = indexValue
                    var mapContext: Context
                    if containerMapping.contains("@id") || containerMapping.contains("@type") {
                        mapContext = activeCtx.previous_context ?? activeCtx
                    } else {
                        mapContext = activeCtx
                    }
                    
                    let index_tdef = mapContext.definition(for: index)
                    if let itc = index_tdef?.context, containerMapping.contains("@type") {
                        mapContext = try self._4_1_2_ctx_processing(activeCtx: &mapContext, localCtx: itc)
                    } else {
                        mapContext = activeCtx
                    }
                    
                    let expandedIndex = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(index), vocab: true)
                    indexValue = indexValue.as_array
                    
                    indexValue = try self._5_1_2_expansion(activeCtx: &mapContext, activeProp: key, element: indexValue, frameExpansion: frameExpansion, ordered: ordered)
                    for item in indexValue.values_from_scalar_or_array {
                        var item = item
                        if containerMapping.contains("@graph") && !item.is_graph_object {
                            let values = item.values_from_scalar_or_array
                            item = JSON.wrap(["@graph": values.map { $0.unwrap() }])
                        }
                        if containerMapping.contains("@index") && indexKey != "@index" && expandedIndex.stringValue != "@none" {
                            let re_expanded_index = try self._5_3_2_value_expand(activeCtx: &activeCtx, activeProp: indexKey, value: JSON.wrap(index))
                            let _expanded_index_key = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(indexKey), vocab: true)
                            guard let expanded_index_key = _expanded_index_key.stringValue else {
                                try self.error(.datatypeError("Expecting string from IRI expansion of @index key but found \(_expanded_index_key)"))
                            }
                            var index_property_values = [re_expanded_index]
                            if let v = item[expanded_index_key] {
                                if v.is_array {
                                    index_property_values.append(contentsOf: v.values_from_scalar_or_array)
                                } else {
                                    index_property_values.append(v)
                                }
                            }
                            item[expanded_index_key] = JSON.wrap(index_property_values.map { $0.unwrap() })
                            if item.is_value_object {
                                let keys = item.keys.sorted()
                                if keys.count != 2 {
                                    try self.apiError(.invalid_value_object)
                                }
                            }
                        } else if containerMapping.contains("@index") && !item.has(key: "@index") && expandedIndex.stringValue != "@none" {
                            item["@index"] = JSON.wrap(index)
                        } else if containerMapping.contains("@id") && !item.has(key: "@id") && expandedIndex.stringValue != "@none" {
                            let expandedIndex = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap(index), documentRelative: true)
                            item["@id"] = expandedIndex
                        } else if containerMapping.contains("@type") && expandedIndex.stringValue != "@none" {
                            var types = [expandedIndex]
                            if let v = item["@type"] {
                                if v.is_array {
                                    types.append(contentsOf: v.values_from_scalar_or_array)
                                } else {
                                    types.append(v)
                                }
                            }
                            item["@type"] = JSON.wrap(types.map { $0.unwrap() })
                        }
                        expandedValue = expandedValue.appending(item)
                    }
                }
            } else {
                expandedValue = try self._5_1_2_expansion(activeCtx: &activeCtx, activeProp: key, element: value, frameExpansion: frameExpansion, ordered: ordered) // # 13.9
            }

            if !expandedValue.defined {
                
                continue
            }
            
            if containerMapping.contains("@list") && !expandedValue.is_list_object {
                expandedValue = expandedValue.wrapped(withMapKey: "@list", asArray: true) // 13.11
            }
            
            if containerMapping.contains("@graph") && !containerMapping.contains("@id") && !containerMapping.contains("@index") {
        //                 # https://github.com/w3c/json-ld-api/issues/311
        //                 # 13.12
                var values = [JSON]()
                for ev in expandedValue.values_from_scalar_or_array {
                    let av = ev.as_array
                    values.append(av.wrapped(withMapKey: "@graph"))
                }
                expandedValue = JSON.wrap(values.map { $0.unwrap() })
            }
            
            if tdef?.reverse ?? false {
                // # 13.13
                let empty = JSON.wrap([:])
                try result.setDefault(key: "@reverse", value: empty)
                let reverseMap = result["@reverse", default: empty]
                defer {
                    result["@reverse"] = reverseMap
                }
                expandedValue = expandedValue.as_array
                for item in expandedValue.values_from_scalar_or_array {
                    if item.is_value_object || item.is_list_object {
                        try self.apiError(.invalid_reverse_property_value)
                    }
                    
                    result[expandedPropertyString] = result[expandedPropertyString, default: JSON.wrap([])].appending(item)
                }
            } else {
                // # 13.14
                let empty = JSON.wrap([])
                try result.setDefault(key: expandedPropertyString, value: empty)
                if expandedValue.is_array {
                    let v = result[expandedPropertyString, default: empty].appending(contentsOf: expandedValue.values_from_scalar_or_array)
                    result[expandedPropertyString] = v
                } else {
                    let v = result[expandedPropertyString, default: empty].appending(expandedValue)
                    result[expandedPropertyString] = v
                }
            }
        }

        try self._5_1_2_expansion_step_14(activeCtx: &activeCtx, typeScopedCtx: &typeScopedCtx, result: &result, activeProp: activeProp, inputType: inputType, nests: &nests, ordered: ordered, frameExpansion: frameExpansion, element: element)
    }
    
    func _5_1_2_expansion_step_14(activeCtx: inout Context, typeScopedCtx: inout Context, result: inout JSON, activeProp: String?, inputType: String, nests: inout [String: JSON], ordered: Bool, frameExpansion: Bool, element: JSON) throws {
        let keys = nests.keys.sorted()
        for nestingKey in keys {
            nests.removeValue(forKey: nestingKey)
            var nestedValues = element[nestingKey, default: JSON.null] // # 14.1
            if !nestedValues.defined {
                nestedValues = JSON.wrap([])
            }
            nestedValues = nestedValues.as_array
            for nestedValue in nestedValues.values_from_scalar_or_array {
                if !nestedValue.is_map {
                    try self.apiError(.invalid_nest_value)
                }
                let keys = nestedValue.keys
                let expandedKeys = try Set(keys.map { try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: JSON.wrap($0)) }.compactMap({$0.stringValue}))
                if expandedKeys.contains("@value") {
                    try self.apiError(.invalid_nest_value)
                }
                try self._5_1_2_expansion_step_13(activeCtx: &activeCtx, typeScopedCtx: &typeScopedCtx, result: &result, activeProp: activeProp, inputType: inputType, nests: &nests, ordered: ordered, frameExpansion: frameExpansion, element: nestedValue)
            }
        }
    }

    func _5_2_2_iri_expansion(activeCtx: inout Context, value _value: JSON, documentRelative: Bool = false, vocab: Bool = false, localCtx: JSON? = nil, defined: [String: Bool] = [:]) throws -> JSON {
        if !_value.defined {
            return _value
        }

        guard case .string(let value) = _value.value else {
            return _value
        }

        if keywords.contains(value) {
            return _value
        }
        
        if value.hasPrefix("@") {
            // /^@[A-Za-z]+$/ looks like a keyword
            let rest = value.dropFirst().drop { (c) -> Bool in
                switch c {
                case "a"..."z":
                    return true
                case "A"..."Z":
                    return true
                default:
                    return false
                }
            }
            if rest.isEmpty {
                // looks like a keyword
                return JSON.null
            }
        }


        if let localCtx = localCtx, let v = localCtx[value] {
            let x = v.stringValue.map { defined[$0] ?? false }
            switch x {
            case true:
                break
            default:
                try self._4_2_2_create_term_definition(activeCtx: &activeCtx, localCtx: localCtx, term: value, defined: defined)
            }
        }
        
        let tdef = activeCtx.definition(for: value)
        if let tdef = tdef {
            let i = tdef.iri_mapping ?? ""
            if keywords.contains(i) {
                return JSON.wrap(i)
            }
        }
        
        if let tdef = tdef, vocab {
            if let i = tdef.iri_mapping {
                return JSON.wrap(i)
            } else {
                return JSON.null
            }
        }
        
        if let colonIndex = value.firstIndex(of: ":"), colonIndex != value.startIndex {
            let components = value.components(separatedBy: ":")
            let prefix = components[0]
            let suffix = components.dropFirst().joined(separator: ":")
            if prefix == "_" || suffix.hasPrefix("//") {
                return JSON.wrap(value)
            }

            if let localCtx = localCtx, localCtx.has(key: prefix) && !(defined[prefix] ?? false) {
                try self._4_2_2_create_term_definition(activeCtx: &activeCtx, localCtx: localCtx, term: prefix, defined: defined)
            }

            if let tdef = activeCtx.definition(for: prefix), let i = tdef.iri_mapping, tdef.prefix_flag {
                let i = i + suffix
                return JSON.wrap(i)
            }
            
            if self._is_absolute_iri(value) {
                return JSON.wrap(value)
            }
        }
        
        if let i = activeCtx.vocab, vocab {
            return JSON.wrap(i)
        } else if documentRelative {
            let base = activeCtx.base
            if let i = URL(string: value, relativeTo: base) {
                return JSON.wrap(i.absoluteString)
            }
        }
        
        return JSON.wrap(value)
    }
    
    func _5_3_2_value_expand(activeCtx: inout Context, activeProp: String?, value: JSON) throws -> JSON {
        let tdef = activeProp.flatMap { activeCtx.definition(for: $0) }
//        guard let tdef = _tdef else {
//            print("Missing term definition for \(activeProp)")
//            try self.apiError(._missingValue)
//        }
        
        if let type_mapping = tdef?.type_mapping {
            // 1
            if type_mapping == "@id" && value.is_string {
                let iri = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: value, documentRelative: true)
                return iri.wrapped(withMapKey: "@id")
            }
            
            if type_mapping == "@vocab" && value.is_string {
                let iri = try self._5_2_2_iri_expansion(activeCtx: &activeCtx, value: value, documentRelative: true, vocab: true)
                return iri.wrapped(withMapKey: "@id")
            }
        }
        
        var result = value.wrapped(withMapKey: "@value")
        if let tm = tdef?.type_mapping, tm != "@id" && tm != "@vocab" && tm != "@none" {
            // 4
            result["@type"] = JSON.wrap(tm)
        } else if value.is_string {
            // 5
            let language = tdef?.language_mapping ?? activeCtx.language
            let direction = tdef?.direction_mapping ?? activeCtx.direction
            
            if let l = language {
                result["@language"] = JSON.wrap(l)
            }
            
            if let d = direction {
                result["@direction"] = JSON.wrap(d.rawValue)
            }
        }
        
        return result
    }
}
