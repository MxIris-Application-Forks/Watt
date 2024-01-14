//
//  Dirent.swift
//  Watt
//
//  Created by David Albert on 1/10/24.
//

import Cocoa

struct FileID {
    let id: NSCopying & NSSecureCoding & NSObjectProtocol
}

extension FileID: Hashable {
    static func == (lhs: FileID, rhs: FileID) -> Bool {
        return lhs.id.isEqual(rhs.id)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id.hash)
    }
}

struct Dirent: Identifiable {
    static let resourceKeys: [URLResourceKey] = [.fileResourceIdentifierKey, .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey]
    static let resourceSet = Set(resourceKeys)

    enum Errors: Error {
        case isNotDirectory(URL)
        case missingAncestor(URL)
        case missingMetadata(URL)
        case missingChild(parent: URL, target: URL)
    }

    let id: FileID
    let name: String
    let url: URL
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let icon: NSImage

    var _children: [Dirent]?
    var children: [Dirent]? {
        if isFolder {
            return _children ?? []
        } else {
            return nil
        }
    }

    var isFolder: Bool {
        isDirectory && !isPackage
    }

    var isLoaded: Bool {
        isFolder && _children != nil
    }

    init(id: FileID, name: String, url: URL, isDirectory: Bool, isPackage: Bool, isHidden: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self._children = nil
    }

    init(for url: URL) throws {
        let url = url.standardizedFileURL
        let rv = try url.resourceValues(forKeys: Dirent.resourceSet)

        guard let resID = rv.fileResourceIdentifier, let isDirectory = rv.isDirectory, let isPackage = rv.isPackage, let isHidden = rv.isHidden else {
            throw Errors.missingMetadata(url)
        }

        self.init(
            id: FileID(id: resID),
            name: rv.name ?? url.lastPathComponent,
            url: url,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isHidden: isHidden
        )
    }

    mutating func updateDescendent(withURL target: URL, using block: (inout Dirent) -> Void) throws {
        if url == target {
            block(&self)
            return
        }

        if !isDirectory {
            throw Errors.isNotDirectory(target)
        }

        if _children == nil {
            throw Errors.missingAncestor(target)
        }

        let targetComponents = target.pathComponents
        for i in 0..<_children!.count {
            let childComponents = _children![i].url.pathComponents

            if childComponents[...] == targetComponents[0..<childComponents.count] {
                try _children![i].updateDescendent(withURL: target, using: block)
                return
            }
        }

        throw Errors.missingChild(parent: url, target: target)
    }
}

extension Dirent: Comparable {
    static func < (lhs: Dirent, rhs: Dirent) -> Bool {
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

