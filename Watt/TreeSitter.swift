//
//  TreeSitter.swift
//  Watt
//
//  Created by David Albert on 9/7/23.
//

import Foundation
import TreeSitter

final class TreeSitterLanguage {
    let languagePointer: UnsafePointer<TSLanguage>

    init(_ language: UnsafePointer<TSLanguage>) {
        self.languagePointer = language
    }

    func query(contentsOf url: URL) throws -> TreeSitterQuery {
        let data = try Data(contentsOf: url)
        return try TreeSitterQuery(data: data, language: languagePointer)
    }
}

protocol TreeSitterParserDelegate: AnyObject {
    func parser(_ parser: TreeSitterParser, readSubstringStartingAt byteIndex: Int) -> Substring?
}

enum TreeSitterInputEncoding {
    case utf8
    case utf16

    var tsInputEncoding: TSInputEncoding {
        switch self {
        case .utf8:
            return TSInputEncodingUTF8
        case .utf16:
            return TSInputEncodingUTF16
        }
    }
}

final class TreeSitterParser {
     enum ParserError: Error {
         case languageIncompatible
     }

    private var pointer: OpaquePointer // TSParser *

    weak var delegate: TreeSitterParserDelegate?
    let encoding: TSInputEncoding

    var language: TreeSitterLanguage {
        // TSParsers can be created without an associated
        // language, but we don't allow that, so it's ok
        // to force unwrap.
        TreeSitterLanguage(ts_parser_language(pointer)!)
    }

    init(language: TreeSitterLanguage, encoding: TreeSitterInputEncoding) throws {
        self.encoding = encoding.tsInputEncoding
        self.pointer = ts_parser_new()

        let success = ts_parser_set_language(self.pointer, language.languagePointer)

        if success == false {
            throw ParserError.languageIncompatible
        }
    }

    deinit {
        ts_parser_delete(pointer)
    }

    func parse(oldTree: TreeSitterTree? = nil) -> TreeSitterTree? {
        let input = TreeSitterTextInput() { [weak self] byteIndex, _ in
            if let self = self {
                return self.delegate?.parser(self, readSubstringStartingAt: byteIndex)
            } else {
                return nil
            }
        }
        // TODO: this might not be necessary. I know that Swift has been
        // changing rules about how long liftimes last. Look into it.
        defer { withExtendedLifetime(input) {} }

        let tsInput = TSInput(
            payload: Unmanaged.passUnretained(input).toOpaque(),
            read: read,
            encoding: encoding
        )

        guard let newTree = ts_parser_parse(pointer, oldTree?.pointer, tsInput) else {
            return nil
        }

        return TreeSitterTree(newTree)
    }
}

typealias TreeSitterReadCallback = (_ byteIndex: Int, _ position: TreeSitterTextPoint) -> Substring?

final class TreeSitterTextInput {
    let callback: TreeSitterReadCallback

    var _buf: UnsafeMutableBufferPointer<Int8>?
    var buf: UnsafeMutableBufferPointer<Int8>? {
        get {
            return _buf
        }
        set {
            _buf?.deallocate()
            _buf = newValue
        }
    }

    deinit {
        buf?.deallocate()
    }

    init(callback: @escaping TreeSitterReadCallback) {
        self.callback = callback
    }
}

fileprivate func read(payload: UnsafeMutableRawPointer?,
                  byteIndex: UInt32,
                  position: TSPoint,
                  bytesRead: UnsafeMutablePointer<UInt32>?) -> UnsafePointer<Int8>? {
    let input: TreeSitterTextInput = Unmanaged.fromOpaque(payload!).takeUnretainedValue()

    guard let s = input.callback(Int(byteIndex), TreeSitterTextPoint(position)) else {
        bytesRead?.pointee = 0
        return nil
    }

    // copy the data into an internally-managed buffer with a lifetime of input
    let buf = UnsafeMutableBufferPointer<CChar>.allocate(capacity: s.utf8.count)
    let n = s.withExistingUTF8 { p in
        p.copyBytes(to: buf)
    }
    precondition(n == s.utf8.count)
    input.buf = buf

    bytesRead?.pointee = UInt32(buf.count)
    return UnsafePointer(buf.baseAddress)
}

struct TreeSitterInputEdit {
    let startByte: Int
    let oldEndByte: Int
    let newEndByte: Int
    let startPoint: TreeSitterTextPoint
    let oldEndPoint: TreeSitterTextPoint
    let newEndPoint: TreeSitterTextPoint

    init(startByte: Int,
         oldEndByte: Int,
         newEndByte: Int,
         startPoint: TreeSitterTextPoint,
         oldEndPoint: TreeSitterTextPoint,
         newEndPoint: TreeSitterTextPoint) {
        self.startByte = startByte
        self.oldEndByte = oldEndByte
        self.newEndByte = newEndByte
        self.startPoint = startPoint
        self.oldEndPoint = oldEndPoint
        self.newEndPoint = newEndPoint
    }
}

extension TreeSitterInputEdit: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterInputEdit startByte=\(startByte) oldEndByte=\(oldEndByte) newEndByte=\(newEndByte)"
            + " startPoint=\(startPoint) oldEndPoint=\(oldEndPoint) newEndPoint=\(newEndPoint)]"
    }
}

extension TSInputEdit {
    init(_ inputEdit: TreeSitterInputEdit) {
        self.init(start_byte: UInt32(inputEdit.startByte),
                  old_end_byte: UInt32(inputEdit.oldEndByte),
                  new_end_byte: UInt32(inputEdit.newEndByte),
                  start_point: inputEdit.startPoint.rawValue,
                  old_end_point: inputEdit.oldEndPoint.rawValue,
                  new_end_point: inputEdit.newEndPoint.rawValue)
    }
}

final class TreeSitterTree {
    let pointer: OpaquePointer // TSTree *

    var root: TreeSitterNode {
        TreeSitterNode(tree: self, node: ts_tree_root_node(pointer))
    }

    init(_ tree: OpaquePointer) {
        self.pointer = tree
    }

    deinit {
        ts_tree_delete(pointer)
    }

    func apply(_ inputEdit: TreeSitterInputEdit) {
        withUnsafePointer(to: TSInputEdit(inputEdit)) { inputEditPointer in
            ts_tree_edit(pointer, inputEditPointer)
        }
    }

    func rangesChanged(comparingTo otherTree: TreeSitterTree) -> [TreeSitterTextRange] {
        var count: UInt32 = 0
        let ptr = ts_tree_get_changed_ranges(pointer, otherTree.pointer, &count)
defer { free(ptr) }

        return UnsafeBufferPointer(start: ptr, count: Int(count)).map { range in
            let startPoint = TreeSitterTextPoint(range.start_point)
            let endPoint = TreeSitterTextPoint(range.end_point)
            let startByte = range.start_byte
            let endByte = range.end_byte
            return TreeSitterTextRange(startPoint: startPoint, endPoint: endPoint, startByte: Int(startByte), endByte: Int(endByte))
        }
    }
}

extension TreeSitterTree: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterTree rootNode=\(root)]"
    }
}

final class TreeSitterNode {
    // Make sure tree doesn't get deallocated before node.
    let tree: TreeSitterTree
    let rawValue: TSNode


    init(tree: TreeSitterTree, node: TSNode) {
        self.tree = tree
        self.rawValue = node
    }

    var startByte: Int {
        Int(ts_node_start_byte(rawValue))
    }

    var endByte: Int {
        Int(ts_node_end_byte(rawValue))
    }

    var range: Range<Int> {
        startByte..<endByte
    }

    var startPoint: TreeSitterTextPoint {
        TreeSitterTextPoint(ts_node_start_point(rawValue))
    }

    var endPoint: TreeSitterTextPoint {
        TreeSitterTextPoint(ts_node_end_point(rawValue))
    }
}

extension TreeSitterNode: CustomDebugStringConvertible {
    var debugDescription: String {
        let s = ts_node_string(rawValue)!
        defer { free(s) }
        return String(cString: s)
    }
}

extension TreeSitterNode: CustomStringConvertible {
    var description: String {
        "[TreeSitterNode startByte=\(startByte) endByte=\(endByte) startPoint=\(startPoint) endPoint=\(endPoint)]"
    }
}

struct TreeSitterTextPoint {
    var row: Int {
        Int(rawValue.row)
    }
    var column: Int {
        Int(rawValue.column)
    }

    let rawValue: TSPoint

    init(_ point: TSPoint) {
        self.rawValue = point
    }

    init(row: Int, column: Int) {
        self.rawValue = TSPoint(row: UInt32(row), column: UInt32(column))
    }
}

extension TreeSitterTextPoint: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterTextPoint row=\(row) column=\(column)]"
    }
}

struct TreeSitterTextRange {
    let rawValue: TSRange

    var startPoint: TreeSitterTextPoint {
        TreeSitterTextPoint(rawValue.start_point)
    }
    var endPoint: TreeSitterTextPoint {
        TreeSitterTextPoint(rawValue.end_point)
    }
    var startByte: Int {
        Int(rawValue.start_byte)
    }
    var endByte: Int {
        Int(rawValue.end_byte)
    }

    init(startPoint: TreeSitterTextPoint, endPoint: TreeSitterTextPoint, startByte: Int, endByte: Int) {
        self.rawValue = TSRange(
            start_point: startPoint.rawValue,
            end_point: endPoint.rawValue,
            start_byte: UInt32(startByte),
            end_byte: UInt32(endByte))
    }
}

extension TreeSitterTextRange: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterTextRange startByte=\(startByte) endByte=\(endByte) startPoint=\(startPoint) endPoint=\(endPoint)]"
    }
}


final class TreeSitterPredicate {
    enum Step {
        case capture(UInt32)
        case string(String)
    }

    let name: String
    let steps: [Step]

    init(name: String, steps: [Step]) {
        self.name = name
        self.steps = steps
    }
}

extension TreeSitterPredicate: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterPredicate name=\(name) steps=\(steps)]"
    }
}

extension TreeSitterPredicate.Step: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .capture(let id):
            return "[TreeSitterPredicate.Step capture=\(id)]"
        case .string(let string):
            return "[TreeSitterPredicate.Step string=\(string)]"
        }
    }
}

enum TreeSitterQueryError: Error {
    case syntax(offset: UInt32)
    case nodeType(offset: UInt32)
    case field(offset: UInt32)
    case capture(offset: UInt32)
    case structure(offset: UInt32)
    case unknown
}

final class TreeSitterQuery {
    let pointer: OpaquePointer

    let language: UnsafePointer<TSLanguage>

    private var patternCount: UInt32 {
        ts_query_pattern_count(pointer)
    }

    init(data: Data, language: UnsafePointer<TSLanguage>) throws {
        var errorOffset: UInt32 = 0
        var errorType: TSQueryError = TSQueryErrorNone

        let pointer = data.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> OpaquePointer? in
            p.withMemoryRebound(to: CChar.self) { p in
                guard let addr = p.baseAddress else {
                    return nil
                }

                // TODO: check the return type of ts_query_new. I'm curious to see if it's optional or not.
                return ts_query_new(language, addr, UInt32(data.count), &errorOffset, &errorType)
            }
        }

        switch errorType.rawValue {
        case 1:
            throw TreeSitterQueryError.syntax(offset: errorOffset)
        case 2:
            throw TreeSitterQueryError.nodeType(offset: errorOffset)
        case 3:
            throw TreeSitterQueryError.field(offset: errorOffset)
        case 4:
            throw TreeSitterQueryError.capture(offset: errorOffset)
        case 5:
            throw TreeSitterQueryError.structure(offset: errorOffset)
        default:
            if let pointer = pointer {
                self.language = language
                self.pointer = pointer
            } else {
                throw TreeSitterQueryError.unknown
            }
        }
    }

    deinit {
        ts_query_delete(pointer)
    }

    func stringValue(forId id: uint) -> String {
        var length: UInt32 = 0
        let p = ts_query_string_value_for_id(pointer, id, &length)!
        return String(bytes: p, count: Int(length), encoding: .utf8)!
    }

    func captureName(forId id: UInt32) -> String {
        var length: UInt32 = 0
        let p = ts_query_capture_name_for_id(pointer, id, &length)!
        return String(bytes: p, count: Int(length), encoding: .utf8)!
    }

    func predicates(forPatternIndex index: UInt32) -> [TreeSitterPredicate] {
        var stepCount: UInt32 = 0
        guard let rawSteps = ts_query_predicates_for_pattern(pointer, index, &stepCount) else {
            return []
        }
        var predicates: [TreeSitterPredicate] = []
        var l = 0
        while l < stepCount {
            var steps: [TreeSitterPredicate.Step] = []
            let name = stringValue(forId: rawSteps.pointee.value_id)
            l += 1
            for i in 1 ..< .max {
                let step = (rawSteps + UnsafePointer<TSQueryPredicateStep>.Stride(i)).pointee
                l += 1
                if step.type == TSQueryPredicateStepTypeCapture {
                    steps.append(.capture(step.value_id))
                } else if step.type == TSQueryPredicateStepTypeString {
                    steps.append(.string(stringValue(forId: step.value_id)))
                } else if step.type == TSQueryPredicateStepTypeDone {
                    break
                }
            }
            let predicate = TreeSitterPredicate(name: name, steps: steps)
            predicates.append(predicate)
        }
        return predicates
    }
}

final class TreeSitterQueryCursor {
    let pointer: OpaquePointer
    let query: TreeSitterQuery
    let tree: TreeSitterTree
    var didExec = false

    init(query: TreeSitterQuery, tree: TreeSitterTree) {
        self.pointer = ts_query_cursor_new()
        self.query = query
        self.tree = tree
    }

    func execute() {
        if !didExec {
            ts_query_cursor_exec(pointer, query.pointer, tree.root.rawValue)
            didExec = true
        }
    }

    deinit {
        ts_query_cursor_delete(pointer)
    }

    // func validCaptures(in stringView: StringView) -> [TreeSitterCapture] {
    //     guard haveExecuted else {
    //         fatalError("Cannot get captures of a query that has not been executed.")
    //     }
    //     var match = TSQueryMatch(id: 0, pattern_index: 0, capture_count: 0, captures: nil)
    //     var result: [TreeSitterCapture] = []
    //     while ts_query_cursor_next_match(pointer, &match) {
    //         let captureCount = Int(match.capture_count)
    //         let captureBuffer = UnsafeBufferPointer<TSQueryCapture>(start: match.captures, count: captureCount)
    //         let captures: [TreeSitterCapture] = captureBuffer.compactMap { capture in
    //             let node = TreeSitterNode(node: capture.node)
    //             let captureName = query.captureName(forId: capture.index)
    //             let predicates = query.predicates(forPatternIndex: UInt32(match.pattern_index))
    //             return TreeSitterCapture(node: node, index: capture.index, name: captureName, predicates: predicates)
    //         }
    //         let match = TreeSitterQueryMatch(captures: captures)
    //         let evaluator = TreeSitterTextPredicatesEvaluator(match: match, stringView: stringView)
    //         result += captures.filter { capture in
    //             capture.byteRange.length > 0 && evaluator.evaluatePredicates(in: capture)
    //         }
    //     }
    //     return result
    // }
}

extension TreeSitterQueryCursor: Sequence {
    struct Iterator: IteratorProtocol {
        let cursor: TreeSitterQueryCursor
        var match: TSQueryMatch
        var iter: UnsafeBufferPointer<TSQueryCapture>.Iterator?

        init(cursor: TreeSitterQueryCursor) {
            self.cursor = cursor
            self.match = TSQueryMatch(id: 0, pattern_index: 0, capture_count: 0, captures: nil)
        }

        mutating func next() -> TreeSitterCapture? {
            if !cursor.didExec {
                cursor.execute()
            }

            if let capture = iter?.next() {
                let node = TreeSitterNode(tree: cursor.tree, node: capture.node)
                let name = cursor.query.captureName(forId: capture.index)
                return TreeSitterCapture(node: node, name: name)
            }

            guard ts_query_cursor_next_match(cursor.pointer, &match) else {
                iter = nil
                return nil
            }

            let buf = UnsafeBufferPointer<TSQueryCapture>(start: match.captures, count: Int(match.capture_count))
            iter = buf.makeIterator()

            return next()
        }
    }

    func makeIterator() -> Iterator {
        Iterator(cursor: self)
    }
}

struct TreeSitterCapture {
    let node: TreeSitterNode
    let name: String

    init(node: TreeSitterNode, name: String) {
        self.node = node
        self.name = name
    }

    var range: Range<Int> {
        node.range
    }
}

extension TreeSitterCapture: CustomDebugStringConvertible {
    var debugDescription: String {
        "[TreeSitterCapture range=\(range) name=\(name)]"
    }
}













// struct TreeSitterLanguage {
//     public var tsLanguage: UnsafePointer<TSLanguage>

//     func query(contentsOf url: URL) throws -> TreeSitterQuery {
//         let data = try Data(contentsOf: url)
//         return try TreeSitterQuery(language: self, data: data)
//     }
// }

// class TreeSitterParser {
//     var tsParser: OpaquePointer // TSParser *

//     convenience init?(language: TreeSitterLanguage) {
//         self.init()

//         guard (try? setLanguage(language)) != nil else {
//             return nil
//         }
//     }

//     init() {
//         tsParser = ts_parser_new()
//     }

//     deinit {
//         ts_parser_delete(tsParser)
//     }
// }

// extension TreeSitterParser {
//     enum ParserError: Error {
//         case languageIncompatible
//         case languageFailure
//         case languageInvalid
//         case unsupportedEncoding(String.Encoding)
//     }

//     public var language: TreeSitterLanguage? {
//         get {
//             return ts_parser_language(tsParser).map { TreeSitterLanguage(tsLanguage: $0) }
//         }
//     }

//     func setLanguage(_ language: TreeSitterLanguage) throws {
//         try setLanguage(language.tsLanguage)
//     }

//     public func setLanguage(_ language: UnsafePointer<TSLanguage>) throws {
//         let success = ts_parser_set_language(tsParser, language)

//         if success == false {
//             throw ParserError.languageFailure
//         }
//     }
// }

// extension TreeSitterParser {
//     public typealias ReadBlock = (Int, TSPoint) -> Substring?

//     class Input {
//         typealias Buffer = UnsafeMutableBufferPointer<Int8>

//         let encoding: TSInputEncoding
//         let readBlock: ReadBlock

//         var _buffer: Buffer?
//         var buffer: Buffer? {
//             get {
//                 return _buffer
//             }
//             set {
//                 _buffer?.deallocate()
//                 _buffer = newValue
//             }
//         }

//         init(encoding: TSInputEncoding, readBlock: @escaping ReadBlock) {
//             self.encoding = encoding
//             self.readBlock = readBlock
//         }

//         deinit {
//             _buffer?.deallocate()
//         }
//     }

//     public func parse(oldTree: TreeSitterTree?, encoding: TSInputEncoding, readBlock: @escaping ReadBlock) -> TreeSitterTree? {
//         let input = Input(encoding: encoding, readBlock: readBlock)

//         let tsInput = TSInput(
//             payload: Unmanaged.passUnretained(input).toOpaque(),
//             read: readFunction,
//             encoding: encoding
//         )

//         guard let newTree = ts_parser_parse(tsParser, oldTree?.tsTree, tsInput) else {
//             return nil
//         }

//         return TreeSitterTree(tsTree: newTree)
//     }
// }

// fileprivate func readFunction(payload: UnsafeMutableRawPointer?, byteIndex: UInt32, position: TSPoint, bytesRead: UnsafeMutablePointer<UInt32>?) -> UnsafePointer<CChar>? {
//     // get our self reference
//     let input: TreeSitterParser.Input = Unmanaged.fromOpaque(payload!).takeUnretainedValue()

//     guard let s = input.readBlock(Int(byteIndex), position) else {
//         bytesRead?.pointee = 0
//         return nil
//     }

    // // copy the data into an internally-managed buffer with a lifetime of input
    // let buffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: s.utf8.count)
    // let n = s.withExistingUTF8 { p in
    //     p.copyBytes(to: buffer)
    // }
    // precondition(n == s.utf8.count)

//     input.buffer = buffer

//     // return to the caller
//     bytesRead?.pointee = UInt32(buffer.count)

//     return UnsafePointer(buffer.baseAddress)
// }

// extension TreeSitterParser {
//     func parse(_ rope: Rope, oldTree: TreeSitterTree?) -> TreeSitterTree? {
//         parse(oldTree: oldTree, encoding: TSInputEncodingUTF8) { byteIndex, position in
//             let i = rope.utf8.index(at: byteIndex)
//             guard let (chunk, offset) = i.read() else {
//                 return nil
//             }

//             let si = chunk.string.utf8Index(at: offset)

//             return chunk.string[si...]
//         }
//     }
// }

// class TreeSitterTree {
//     var tsTree: OpaquePointer // TSTree *

//     init(tsTree: OpaquePointer) {
//         self.tsTree = tsTree
//     }

//     var root: TreeSitterNode {
//         TreeSitterNode(tree: self, tsNode: ts_tree_root_node(tsTree))
//     }

//     func edit(_ inputEdit: TreeSitterInputEdit) {
//         withUnsafePointer(to: inputEdit.tsInputEdit) { ptr -> Void in
//             ts_tree_edit(tsTree, ptr)
//         }
//     }
// }

// struct TreeSitterNode {
//     var tree: TreeSitterTree
//     var tsNode: TSNode

//     init(tree: TreeSitterTree, tsNode: TSNode) {
//         self.tree = tree
//         self.tsNode = tsNode
//     }
// }

// extension TreeSitterNode: CustomDebugStringConvertible {
//     var debugDescription: String {
//         let s = ts_node_string(tsNode)
//         defer { free(s) }
//         return String(cString: s!)
//     }
// }

// final class TreeSitterQuery: Sendable {
//     public enum QueryError: Error {
//         case none
//         case syntax(UInt32)
//         case nodeType(UInt32)
//         case field(UInt32)
//         case capture(UInt32)
//         case structure(UInt32)
//         case unknown(UInt32)

//         init(offset: UInt32, internalError: TSQueryError) {
//             switch internalError {
//             case TSQueryErrorNone:
//                 self = .none
//             case TSQueryErrorSyntax:
//                 self = .syntax(offset)
//             case TSQueryErrorNodeType:
//                 self = .nodeType(offset)
//             case TSQueryErrorField:
//                 self = .field(offset)
//             case TSQueryErrorCapture:
//                 self = .capture(offset)
//             case TSQueryErrorStructure:
//                 self = .structure(offset)
//             default:
//                 self = .unknown(offset)
//             }
//         }
//     }

//     let tsQuery: OpaquePointer
// //    let predicateList: [[Predicate]]

//     /// Construct a query object from scm data
//     ///
//     /// This operation has do to a lot of work, especially if any
//     /// patterns contain predicates. You should expect it will
//     /// be expensive.
//     init(language: TreeSitterLanguage, data: Data) throws {
//         let dataLength = data.count
//         var errorOffset: UInt32 = 0
//         var queryError: TSQueryError = TSQueryErrorNone

//         let tsQuery = data.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> OpaquePointer? in
//             p.withMemoryRebound(to: CChar.self) { p in
//                 guard let addr = p.baseAddress else {
//                     return nil
//                 }

//                 return ts_query_new(language.tsLanguage,
//                                     addr,
//                                     UInt32(dataLength),
//                                     &errorOffset,
//                                     &queryError)
//             }
//         }

//         guard let tsQuery else {
//             throw QueryError(offset: errorOffset, internalError: queryError)
//         }

//         self.tsQuery = tsQuery
//         // self.predicateList = try PredicateParser().predicates(in: queryPtr)
//     }

//     deinit {
//         ts_query_delete(tsQuery)
//     }

//     var patternCount: Int {
//         return Int(ts_query_pattern_count(tsQuery))
//     }

//     var captureCount: Int {
//         return Int(ts_query_capture_count(tsQuery))
//     }

//     var stringCount: Int {
//         return Int(ts_query_string_count(tsQuery))
//     }

// 	/// Run a query
// 	///
// 	/// Note that both the node **and** the tree is is part of
// 	/// must remain valid as long as the query is being used.
// 	///
// 	/// - Parameter node: the root node for the query
// 	/// - Parameter tree: keep an optional reference to the tree
//     // public func execute(node: Node, in tree: Tree? = nil) -> QueryCursor {
//     //     let cursor = QueryCursor()

//     //     cursor.execute(query: self, node: node, in: tree)

//     //     return cursor
//     // }

//     // public func captureName(for id: Int) -> String? {
//     //     var length: UInt32 = 0

//     //     guard let cStr = ts_query_capture_name_for_id(internalQuery, UInt32(id), &length) else {
//     //         return nil
//     //     }

//     //     return String(cString: cStr)
//     // }

//     // public func stringName(for id: Int) -> String? {
//     //     var length: UInt32 = 0

//     //     guard let cStr = ts_query_string_value_for_id(internalQuery, UInt32(id), &length) else {
//     //         return nil
//     //     }

//     //     return String(cString: cStr)
//     // }

//     // public func predicates(for patternIndex: Int) -> [Predicate] {
//     //     return predicateList[patternIndex]
//     // }

//     // public var hasPredicates: Bool {
//     //     for i in 0..<patternCount {
//     //         if predicates(for: i).isEmpty == false {
//     //             return true
//     //         }
//     //     }

//     //     return false
//     // }
// }

// class TreeSitterQueryCursor {
//     let tsQueryCursor: OpaquePointer
//     let tree: TreeSitterTree // need to keep the tree alive as long as the cursor exists
//     var activeQuery: TreeSitterQuery?

//     init(tree: TreeSitterTree) {
//         self.tsQueryCursor = ts_query_cursor_new()
//         self.tree = tree
//     }

//     func execute(query: TreeSitterQuery) {
//         activeQuery = query
//         ts_query_cursor_exec(tsQueryCursor, query.tsQuery, tree.root.tsNode)
//     }

//     deinit {
//         ts_query_cursor_delete(tsQueryCursor)
//     }
// }

// extension TreeSitterQueryCursor: Sequence, IteratorProtocol {
//     func next() -> TreeSitterQueryMatch? {
//         var match = TSQueryMatch(id: 0, pattern_index: 0, capture_count: 0, captures: nil)

//         guard ts_query_cursor_next_match(tsQueryCursor, &match) else {
//             return nil
//         }

//         return TreeSitterQueryMatch(queryCursor: self, tsQueryMatch: match, query: activeQuery!)
//     }
// }

// class TreeSitterQueryMatch {
//     let tsQueryMatch: TSQueryMatch

//     // The query cursor keeps the tree alive, which we need
//     // because each TSQueryCapture contains a TSNode pointer.
//     //
//     // I believe the memory used by TSQueryMatch.captures is
//     // also kept alive by the query cursor.
//     let queryCursor: TreeSitterQueryCursor
//     let query: TreeSitterQuery
//     let captures: [TreeSitterQueryCapture]

//     init(queryCursor: TreeSitterQueryCursor, tsQueryMatch: TSQueryMatch, query: TreeSitterQuery) {
//         self.queryCursor = queryCursor
//         self.query = query
//         self.tsQueryMatch = tsQueryMatch

//         let buf = UnsafeBufferPointer<TSQueryCapture>(start: tsQueryMatch.captures, count: Int(tsQueryMatch.capture_count))
//         self.captures = buf.map { TreeSitterQueryCapture(tsQueryCapture: $0, query: query)}
//     }
// }

// struct TreeSitterQueryCapture {
//     let name: String
//     let range: Range<Int>
//     TODO: must retain its Node so that the tree will be retained.

//     init(tsQueryCapture: TSQueryCapture, query: TreeSitterQuery) {
//         var length: UInt32 = 0
//         let p = ts_query_capture_name_for_id(query.tsQuery, tsQueryCapture.index, &length)!
//         self.name = String(bytes: p, count: Int(length), encoding: .utf8)!

//         let start = ts_node_start_byte(tsQueryCapture.node)
//         let end = ts_node_end_byte(tsQueryCapture.node)
//         self.range = Int(start)..<Int(end)
//     }
// }

// struct TreeSitterPoint {
//     let row: Int
//     let column: Int

//     init(row: Int, column: Int) {
//         self.row = row
//         self.column = column
//     }

//     init(_ point: TSPoint) {
//         self.row = Int(point.row)
//         self.column = Int(point.column)
//     }

//     var tsPoint: TSPoint {
//         TSPoint(row: UInt32(row), column: UInt32(column))
//     }
// }

// struct TreeSitterInputEdit {
//     let startByte: Int
//     let oldEndByte: Int
//     let newEndByte: Int
//     let startPoint: TreeSitterPoint
//     let oldEndPoint: TreeSitterPoint
//     let newEndPoint: TreeSitterPoint

//     init(startByte: Int, oldEndByte: Int, newEndByte: Int, startPoint: TreeSitterPoint, oldEndPoint: TreeSitterPoint, newEndPoint: TreeSitterPoint) {
//         self.startByte = startByte
//         self.oldEndByte = oldEndByte
//         self.newEndByte = newEndByte
//         self.startPoint = startPoint
//         self.oldEndPoint = oldEndPoint
//         self.newEndPoint = newEndPoint
//     }

//     var tsInputEdit: TSInputEdit {
//         TSInputEdit(start_byte: UInt32(startByte),
//                     old_end_byte: UInt32(oldEndByte),
//                     new_end_byte: UInt32(newEndByte),
//                     start_point: startPoint.tsPoint,
//                     old_end_point: oldEndPoint.tsPoint,
//                     new_end_point: newEndPoint.tsPoint)
//     }
// }
