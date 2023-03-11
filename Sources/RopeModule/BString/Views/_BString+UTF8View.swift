//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if swift(>=5.8)

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension _BString {
  internal struct UTF8View: Sendable {
    var _base: _BString

    @inline(__always)
    init(_base: _BString) {
      self._base = _base
    }
  }

  @inline(__always)
  internal var utf8: UTF8View {
    UTF8View(_base: self)
  }

  internal init(_ utf8: UTF8View) {
    self = utf8._base
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension _BString.UTF8View: Equatable {
  internal static func ==(left: Self, right: Self) -> Bool {
    _BString.utf8IsEqual(left._base, to: right._base)
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension _BString.UTF8View: Hashable {
  internal func hash(into hasher: inout Hasher) {
    _base.hashUTF8(into: &hasher)
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension _BString.UTF8View: Sequence {
  typealias Element = UInt8
  typealias Iterator = _BString.UTF8Iterator

  internal func makeIterator() -> _BString.UTF8Iterator {
    _base.makeUTF8Iterator()
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension _BString.UTF8View: BidirectionalCollection {
  typealias Index = _BString.Index
  typealias SubSequence = _BSubstring.UTF8View

  @inline(__always)
  internal var startIndex: Index { _base.startIndex }

  @inline(__always)
  internal var endIndex: Index { _base.endIndex }

  internal var count: Int { _base.utf8Count }

  @inline(__always)
  internal func index(after i: Index) -> Index {
    _base.utf8Index(after: i)
  }

  @inline(__always)
  internal func index(before i: Index) -> Index {
    _base.utf8Index(before: i)
  }

  @inline(__always)
  internal func index(_ i: Index, offsetBy distance: Int) -> Index {
    _base.utf8Index(i, offsetBy: distance)
  }

  internal func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    _base.utf8Index(i, offsetBy: distance, limitedBy: limit)
  }

  internal func distance(from start: Index, to end: Index) -> Int {
    _base.utf8Distance(from: start, to: end)
  }

  internal subscript(position: Index) -> UInt8 {
    _base[utf8: position]
  }

  internal subscript(bounds: Range<Index>) -> _BSubstring.UTF8View {
    _BSubstring.UTF8View(_base, in: bounds)
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension _BString.UTF8View {
  internal func index(roundingDown i: Index) -> Index {
    _base.utf8Index(roundingDown: i)
  }

  internal func index(roundingUp i: Index) -> Index {
    _base.utf8Index(roundingUp: i)
  }
}

#endif
