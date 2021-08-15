//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension _BTree {
  /// Provides an interface for efficiently constructing a filled B-Tree from sorted data.
  ///
  /// This type has a few advantages when constructing a B-Tree over other approaches such as manually
  /// inserting each element or using a cursor:
  ///
  /// This works by maintaing a list of saplings and a view of the node currently being modified. For example
  /// the following tree:
  ///
  ///             ┌─┐
  ///             │D│
  ///         ┌───┴─┴───┐
  ///         │         │
  ///        ┌┴┐       ┌┴┐
  ///        │B│       │F│
  ///      ┌─┴─┴─┐   ┌─┴─┴─┐
  ///      │     │   │     │
  ///     ┌┴┐   ┌┴┐ ┌┴┐   ┌┴┐
  ///     │A│   │C│ │E│   │G│
  ///     └─┘   └─┘ └─┘   └─┘
  ///
  /// Would be represented in the following state:
  ///
  ///                 ┌─┐
  ///      Seedling:  │G│
  ///                 └─┘
  ///
  ///                    ┌─┐
  ///                    │B│       ┌─┐
  ///      Saplings:   ┌─┴─┴─┐     │E│
  ///                  │     │     └─┘
  ///                 ┌┴┐   ┌┴┐
  ///                 │A│   │C│
  ///                 └─┘   └─┘
  ///
  ///                 ┌─┐          ┌─┐
  ///     Seperators: │D│          │F│
  ///                 └─┘          └─┘
  ///
  /// While the diagrams above represent a binary-tree, the representation of a B-Tree in the builder is
  /// directly analogous to this. By representing the state this way. Append operations can be efficiently
  /// performed, and the tree can also be efficiently reconstructed.
  ///
  /// Appending works by filling in a seedling, once a seedling is full, and an associated seperator has been
  /// provided, the seedling-seperator pair can be appended to the stack.
  @usableFromInline
  internal struct Builder {
    @usableFromInline
    enum State {
      /// The builder needs to add a seperator to the node
      case addingSeperator
      
      /// The builder needs to try to append to the seedling node.
      case appendingToSeedling
    }
    
    @usableFromInline
    internal var _saplings: [Node]
    
    @usableFromInline
    internal var _seperators: [Element]
    
    @usableFromInline
    internal var _seedling: Node?
    
    @inlinable
    @inline(__always)
    internal var seedling: Node {
      get {
        assert(_seedling != nil,
               "Simultaneous access or access on consumed builder.")
        return _seedling.unsafelyUnwrapped
      }
      _modify {
        assert(_seedling != nil,
               "Simultaneous mutable access or mutable access on consumed builder.")
        var value = _seedling.unsafelyUnwrapped
        _seedling = nil
        defer { _seedling = value }
        yield &value
      }
    }
    
    @usableFromInline
    internal var state: State
    
    @usableFromInline
    internal let leafCapacity: Int
    
    @usableFromInline
    internal let internalCapacity: Int
    
    /// Creates a new B-Tree builder with default capacities
    @inlinable
    @inline(__always)
    internal init() {
      self.init(
        leafCapacity: _BTree.defaultLeafCapacity,
        internalCapacity: _BTree.defaultInternalCapacity
      )
    }
    
    /// Creates a new B-Tree builder with a custom uniform capacity configuration
    /// - Parameters:
    ///   - capacity: The amount of elements per node.
    @inlinable
    @inline(__always)
    internal init(capacity: Int) {
      self.init(leafCapacity: capacity, internalCapacity: capacity)
    }
    
    /// Creates a new B-Tree builder with a custom capacity configuration
    /// - Parameters:
    ///   - capacity: The amount of elements per node.
    @inlinable
    @inline(__always)
    internal init(
      leafCapacity: Int,
      internalCapacity: Int
    ) {
      assert(leafCapacity > 1 && internalCapacity > 1,
             "Capacity must be greater than one")
      
      self._saplings = []
      self._seperators = []
      self.state = .appendingToSeedling
      self._seedling = Node(withCapacity: leafCapacity, isLeaf: true)
      self.leafCapacity = leafCapacity
      self.internalCapacity = internalCapacity
    }
    
    /// Pops a sapling and it's associated seperator
    @inlinable
    @inline(__always)
    internal mutating func popSapling()
      -> (leftNode: Node, seperator: Element)? {
      return _saplings.isEmpty ? nil : (
        leftNode: _saplings.removeLast(),
        seperator: _seperators.removeLast()
      )
    }
    
    /// Appends a sapling with an associated seperator
    @inlinable
    @inline(__always)
    internal mutating func appendSapling(
      _ sapling: __owned Node,
      seperatedBy seperator: Element
    ) {
      _saplings.append(sapling)
      _seperators.append(seperator)
    }
    
    /// Appends a sequence of sorted values to the tree
    @inlinable
    @inline(__always)
    internal mutating func append<S: Sequence>(
      contentsOf sequence: S
    ) where S.Element == Element {
      for element in sequence {
        self.append(element)
      }
    }
    
    /// Appends a new element to the tree
    /// - Parameter element: Element which is after all previous elements in sorted order.
    @inlinable
    @inline(__always)
    internal mutating func append(_ element: __owned Element) {
      switch state {
      case .addingSeperator:
        completeSeedling(withSeperator: element)
        state = .appendingToSeedling

      case .appendingToSeedling:
        let isFull: Bool = seedling.update { handle in
          handle.appendElement(element)
          return handle.isFull
        }
        
        if _slowPath(isFull) {
          state = .addingSeperator
        }
      }
    }
    
    
    
    /// Declares that the current seedling is finished with insertion and creates a new seedling to
    /// further operate on.
    @inlinable
    @inline(__always)
    internal mutating func completeSeedling(
      withSeperator newSeperator: __owned Element
    ) {
      var sapling = Node(withCapacity: leafCapacity, isLeaf: true)
      swap(&sapling, &self.seedling)
      
      // Prepare a new sapling to insert.
      // There are a few invariants we're thinking about here:
      //   - Leaf nodes are coming in fully filled. We can treat them as atomic
      //     bits
      //   - The stack has saplings of decreasing depth.
      //   - Saplings on the stack are completely filled except for their roots.
      if case (var previousSapling, let seperator)? = self.popSapling() {
        let saplingDepth = sapling.storage.header.depth
        let previousSaplingDepth = previousSapling.storage.header.depth
        let previousSaplingIsFull = previousSapling.read({ $0.isFull })
        
        assert(previousSaplingDepth >= saplingDepth,
               "Builder invariant failure.")
        
        if saplingDepth == previousSaplingDepth && previousSaplingIsFull {
          // This is when two nodes are full:
          //
          //              ┌───┐   ┌───┐
          //              │ A │   │ C │
          //              └───┘   └───┘
          //                ▲       ▲
          //                │       │
          //      previousSapling  sapling
          //
          // We then use the seperator (B) to transform this into a subtree of a
          // depth increase:
          //     ┌───┐
          //     │ B │ ◄─── sapling
          //    ┌┴───┴┐
          //    │     │
          //  ┌─┴─┐ ┌─┴─┐
          //  │ A │ │ C │
          //  └───┘ └───┘
          // If the sapling is full. We create a splinter. This is when the
          // depth of our B-Tree increases
          sapling = _Node(
            leftChild: previousSapling,
            seperator: seperator,
            rightChild: sapling,
            capacity: internalCapacity
          )
        } else if saplingDepth + 1 == previousSaplingDepth && !previousSaplingIsFull {
          // This is when we can append the node with the seperator:
          //
          //     ┌───┐
          //     │ B │ ◄─ previousSapling
          //    ┌┴───┴┐
          //    │     │
          //  ┌─┴─┐ ┌─┴─┐      ┌───┐
          //  │ A │ │ C │      │ E │ ◄─ sapling
          //  └───┘ └───┘      └───┘
          //
          // We then use the seperator (D) to append this to previousSapling.
          //      ┌────┬───┐
          //      │  B │ D │   ◄─ sapling
          //     ┌┴────┼───┴┐
          //     │     │    │
          //   ┌─┴─┐ ┌─┴─┐ ┌┴──┐
          //   │ A │ │ C │ │ E │
          //   └───┘ └───┘ └───┘
          previousSapling.update {
            $0.appendElement(seperator, withRightChild: sapling)
          }
          sapling = previousSapling
        } else {
          // In this case, we need to work on creating a new sapling. Say we
          // have:
          //
          //      ┌────┬───┐
          //      │  B │ D │ ◄─ previousSapling
          //     ┌┴────┼───┴┐
          //     │     │    │
          //   ┌─┴─┐ ┌─┴─┐ ┌┴──┐     ┌───┐
          //   │ A │ │ C │ │ E │     │ G │ ◄─ sapling
          //   └───┘ └───┘ └───┘     └───┘
          //
          // Where previousSapling is full. We'll commit sapling and keep
          // working on it until it is of the same depth as `previousSapling`.
          // Once it is the same depth, we can join the nodes.
          //
          // The goal is once we have a full tree of equal depth:
          //
          //      ┌────┬───┐           ┌────┬───┐
          //      │  B │ D │           │  H │ J │
          //     ┌┴────┼───┴┐         ┌┴────┼───┴┐
          //     │     │    │         │     │    │
          //   ┌─┴─┐ ┌─┴─┐ ┌┴──┐    ┌─┴─┐ ┌─┴─┐ ┌┴──┐
          //   │ A │ │ C │ │ E │    │ G │ │ I │ │ K │
          //   └───┘ └───┘ └───┘    └───┘ └───┘ └───┘
          //
          // We can string them together using the previous cases.
          self.appendSapling(previousSapling, seperatedBy: seperator)
        }
      }
      
      self.appendSapling(sapling, seperatedBy: newSeperator)
    }
    
    /// Finishes building a tree.
    ///
    /// This consumes the builder and it is no longer valid to operate on after this.
    ///
    /// - Returns: A usable, fully-filled B-Tree
    @inlinable
    @inline(__always)
    internal mutating func finish() -> _BTree {
      var root: Node = seedling
      _seedling = nil
      
      while case (var sapling, let seperator)? = self.popSapling() {
        root = _Node.join(
          &sapling,
          with: &root,
          seperatedBy: seperator,
          capacity: internalCapacity
        )
      }
      
      let tree = _BTree(rootedAt: root, internalCapacity: internalCapacity)
      tree.checkInvariants()
      return tree
    }
  }
}
