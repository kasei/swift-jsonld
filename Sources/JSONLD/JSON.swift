//
//  JSON.swift
//  JSONLD
//
//  Created by GWilliams on 3/12/20.
//  Copyright © 2020 GWilliams. All rights reserved.
//

import Foundation

extension NSNumber {
    var isBool: Bool {
        return type(of: self) == type(of: NSNumber(booleanLiteral: true))
    }
}

extension Dictionary {
    func has(key: Key) -> Bool {
        if let _ = self[key] {
            return true
        } else {
            return false
        }
    }
}

public struct JSON: Equatable {
    public enum Value {
        case null
        case bool(Bool)
        case string(String)
        case number(Double)
        case array([JSON])
        case map([String: JSON])
    }
    var _wrappedValue: Any?
    
    static func validateValue(_ _v: Any) {
        if let _ = _v as? JSON {
            fatalError("Bad double-wrapping of JSON value")
        } else if let _ = _v as? String {
        } else if let _ = _v as? NSNumber {
        } else if let a = _v as? [Any] {
            for v in a {
                validateValue(v)
            }
        } else if let d = _v as? [String:Any] {
            for v in d.values {
                validateValue(v)
            }
        } else {
            fatalError("Attempted wrapping of invalid value: \(_v)")
        }
    }
    
    init(_wrappedValue: Any?) {
        self._wrappedValue = _wrappedValue
//        if let _v = _wrappedValue {
//            JSON.validateValue(_v)
//        }
    }
    
    static let null = JSON(_wrappedValue: nil)

    public var value : Value {
        guard let _v = _wrappedValue else {
            return .null
        }
        if let s = _v as? String {
            return .string(s)
        } else if let n = _v as? NSNumber {
            if n.isBool {
                return .bool(n.boolValue)
            } else {
                return .number(n.doubleValue)
            }
        } else if let a = _v as? [Any] {
            return .array(a.map { JSON(_wrappedValue: $0) })
        } else if let d = _v as? [String:Any] {
            var dd = [String: JSON]()
            for (k, v) in d {
                dd[k] = JSON(_wrappedValue: v)
            }
            return .map(dd)
        } else {
            return .null
        }
    }

    public func wrapped(withMapKey key: String, asArray: Bool = false) -> JSON {
        if asArray {
            let values = self.values_from_scalar_or_array.map { $0.unwrap() }
            return JSON(_wrappedValue: [key: values])
        } else {
            return JSON(_wrappedValue: [key: _wrappedValue])
        }
    }
    
    public static func wrap(_ value: Any) -> JSON {
        return JSON(_wrappedValue: value)
    }
    
    public func unwrap() -> Any {
        switch self.value {
        case .null:
            return NSNull()
        case .array(let a):
            return a.map { $0.unwrap() }
        case .bool(let b):
            return NSNumber(booleanLiteral: b)
        case .string(let v):
            return v
        case .number(let v):
            return NSNumber(floatLiteral: v)
        case .map(let d):
            let s = d.map {
                ($0.key, $0.value.unwrap())
            }
            let d = Dictionary(uniqueKeysWithValues: s)
            return d
        }
    }
    
    public static func decode(_ data: Data) -> JSON? {
        guard let j = try? JSONSerialization.jsonObject(with: data) else {
            print("*** Failed to parse JSON")
            return nil
        }
        return JSON(_wrappedValue: j)
    }

    public subscript(index: Int) -> JSON? {
        if case .array(let a) = self.value {
            return a[index]
        }
        return nil
    }

    public subscript(index: String) -> JSON? {
        get {
            guard let _v = _wrappedValue else {
                return nil
            }
            if let d = _v as? [String:Any], let value = d[index] {
                return JSON(_wrappedValue: value)
            }
            return nil
        }
        set(newValue) {
            if is_map {
                var _wd = _wrappedValue as! [String:Any]
                _wd[index] = newValue?.unwrap()
                _wrappedValue = _wd
            }
        }
    }

    public subscript(index: String, default defaultValue: JSON) -> JSON {
        get {
            guard let _v = _wrappedValue else {
                return defaultValue
            }
            if let d = _v as? [String:Any], let value = d[index] {
                return JSON(_wrappedValue: value)
            }
            return defaultValue
        }
        set(newValue) {
            if is_map {
                var _wd = _wrappedValue as! [String:Any]
                _wd[index] = newValue.unwrap()
                _wrappedValue = _wd
            }
        }
    }
    
    public mutating func removeValue(forKey key: String) throws {
        if is_map {
            var _wd = _wrappedValue as! [String:Any]
            _wd.removeValue(forKey: key)
            _wrappedValue = _wd
        } else {
            throw JSONLDError.datatypeError("Expecting map in removeValue(forKey:) call")
        }
    }

    public static func == (lhs: JSON, rhs: JSON) -> Bool {
        switch (lhs.value, rhs.value) {
        case (.null, .null):
            return true
        case (.array(let a), .array(let b)):
            return a == b
        case (.bool(let a), .bool(let b)):
            return a == b
        case (.string(let a), .string(let b)):
            return a == b
        case (.number(let a), .number(let b)):
            return a == b
        case (.map(let a), .map(let b)):
            return a == b
        default:
            return false
        }
    }
}

extension JSON { // Helper methods
    var values_from_scalar_or_array: [JSON] { // TODO: rename to just `values`
        switch self.value {
        case .array(let a):
            return a
        default:
            return [self]
        }
    }
    
    var defined: Bool {
        switch self.value {
        case .null:
            return false
        default:
            return true
        }
    }

    var is_boolean: Bool {
        if let n = _wrappedValue as? NSNumber {
            return n.isBool
        }
        return false
    }
    
    var as_array: JSON {
        if is_array {
            return self
        } else {
            return JSON.wrap(self.values_from_scalar_or_array.map { $0.unwrap() })
        }
    }
    
    func appending(_ item: JSON) -> JSON {
        let items = values_from_scalar_or_array + [item]
        let values = items.map { $0.unwrap() }
        return JSON.wrap(values)
    }
    
    func appending<C>(contentsOf items: C) -> JSON where C: Collection, C.Element == JSON {
        let items = values_from_scalar_or_array + items
        let values = items.map { $0.unwrap() }
        return JSON.wrap(values)
    }
    
    mutating func setDefault(key: String, value: JSON) throws {
        guard is_map else {
            throw JSONLDError.datatypeError("Expecting map value in setDefault but found: \(self)")
        }
        if !has(key: key) {
            self[key] = value
        }
    }
    
    var is_array: Bool {
        switch self.value {
        case .array:
            return true
        default:
            return false
        }
    }

    func has(key: String) -> Bool {
        guard let _v = _wrappedValue else {
            return false
        }
        if let d = _v as? [String:Any], let _ = d[key] {
            return true
        }
        return false
    }

    var is_map: Bool {
        switch self.value {
        case .map:
            return true
        default:
            return false
        }
    }
    
    var is_scalar: Bool {
        switch self.value {
        case .bool, .number, .string:
            return true
        default:
            return false
        }
    }
    
    var is_string: Bool {
        switch self.value {
        case .string:
            return true
        default:
            return false
        }
    }
    
    var pairs: [(String, JSON)] {
        switch self.value {
        case .map(let dd):
            return Array(dd)
        default:
            return []
        }
    }
    
    var keys: [String] {
        switch self.value {
        case .map(let dd):
            return dd.keys.sorted()
        default:
            return []
        }
    }
    
    var booleanValue: Bool {
        if case .bool(let b) = self.value {
            return b
        }
        return false
    }
    
    var stringValue: String? {
        switch self.value {
        case .string(let s):
            return s
        default:
            return nil
        }
    }
    
    var doubleValue: Double? {
        switch self.value {
        case .number(let v):
            return v
        default:
            return nil
        }
    }
    
    var is_integer: Bool {
        switch self.value {
        case .number(let v):
            let r = v.truncatingRemainder(dividingBy: 1)
            return r == 0.0
        default:
            return false
        }
    }
    
    var is_numeric: Bool {
        switch self.value {
        case .number:
            return true
        default:
            return false
        }
    }
    
    mutating func append(_ value: JSON) {
        guard case .array(var a) = self.value else {
            return
        }
        a.append(value)
        _wrappedValue = a
    }
    
    mutating func append<S>(contentsOf newElements: S) where JSON == S.Element, S : Sequence {
        guard case .array(var a) = self.value else {
            return
        }
        a.append(contentsOf: newElements)
        _wrappedValue = a
    }
    
    mutating func add_value(key: String, value: JSON, as_array: Bool = false) throws {
        var value = value
        if as_array && !is_array {
            value = JSON.wrap([value])
        }
        
        guard case .map = self.value else {
            throw JSONLDError.datatypeError("Expecting a map but found \(value.value)")
        }
        
        if let _ = self[key] {
            if let v = self[key] {
                if !v.is_array {
                    self[key] = JSON.wrap([v])
                }
            }
            
            guard var list = self[key] else {
                throw JSONLDError.missingValue
            }
            if value.is_array {
                list.append(contentsOf: value.values_from_scalar_or_array)
            } else {
                list.append(value)
            }
        } else {
            self[key] = value
        }
    }
    
    func _is_map(with key: String) -> Bool {
        guard case .map(let dd) = self.value else {
            return false
        }
        if let _ = dd[key] {
            return true
        }
        return false
    }
    
    var is_value_object: Bool {
        return _is_map(with: "@value")
    }
    
    var is_list_object: Bool {
        return _is_map(with: "@list")
    }
    
    var is_graph_object: Bool {
        return _is_map(with: "@graph")
    }

    var is_simple_graph_object: Bool {
        if !is_graph_object {
            return false
        }
        return !_is_map(with: "@id")
    }
    
    var is_node_object: Bool {
        guard case .map(let dd) = self.value else {
            return false
        }
        for p in ["@value", "@list", "@set"] {
            if let _ = dd[p] {
                return false
            }
        }
        // TODO: check that value "is not the top-most map in the JSON-LD document consisting of no other entries than @graph and @context."
        return true
    }
    
    var is_default_object: Bool {
        guard self.is_map else {
            return false
        }
        for p in ["@value", "@list", "@set"] {
            if self.has(key: p) {
                return false
            }
        }
        return true
    }
    
/*
 _is_abs_iri
 _is_iri
 _make_relative_iri
 _load_document
 _cm_contains
 _cm_contains_any
 _ctx_term_defn
 _ctx_contains_protected_terms
 _ctx_protected_terms
 _is_well_formed_graph_node
 _is_well_formed_language
 _is_well_formed_datatype
 _is_well_formed_iri
 _is_well_formed_graphname
 _is_well_formed
 _is_prefix_of

 */
}


extension JSON: CustomDebugStringConvertible {
    public var debugDescription: String {
        let u = unwrap()
        let options : JSONSerialization.WritingOptions
        if #available(OSX 10.15, *) {
            options = [.fragmentsAllowed, .prettyPrinted, .withoutEscapingSlashes]
        } else {
            options = [.fragmentsAllowed, .prettyPrinted]
        }
        
        guard let d = try? JSONSerialization.data(withJSONObject: u, options: options) else {
            return "(invalid JSON serialization)"
        }
        guard let s = String(data: d, encoding: .utf8) else {
            return "(invalid utf-8 serialization)"
        }
        return s
    }
}
