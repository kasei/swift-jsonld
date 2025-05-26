//
//  Expansion.swift
//  JSONLD
//
//  Created by GWilliams on 3/16/20.
//

import Foundation

public extension JSONLD {
    func expand(data: JSON, expandContext: JSON? = nil, preProcessedContext: Context? = nil) throws -> JSON {
        var ctx = preProcessedContext ?? newContext(base: self.base)
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
}

extension JSONLD {
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
            if ((!expandedProperty.defined) || ((!expandedPropertyString.contains(":")) && !JSONLDKeywords.contains(expandedPropertyString))) {
                continue
            }
            
            var expandedValue: JSON = .null
            if JSONLDKeywords.contains(expandedPropertyString) {
                if activeProp == "@reverse" {
                    try self.apiError(.invalid_reverse_property_map)
                }
                if let epKey = expandedProperty.stringValue, let _ = result[epKey] {
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
                        let wellFormed = true // # TODO: check BCP47 well-formedness of $item
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
        
        if JSONLDKeywords.contains(value) {
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
            if JSONLDKeywords.contains(i) {
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
