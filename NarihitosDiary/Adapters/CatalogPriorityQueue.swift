struct CatalogPriorityQueue<Element: Sendable>: Sendable {
  private var elements: [Element] = []
  private let precedes: @Sendable (Element, Element) -> Bool

  init(precedes: @escaping @Sendable (Element, Element) -> Bool) { self.precedes = precedes }
  var first: Element? { elements.first }
  var isEmpty: Bool { elements.isEmpty }

  mutating func insert(_ value: Element) {
    elements.append(value)
    var index = elements.count - 1
    while index > 0 {
      let parent = (index - 1) / 2
      guard precedes(elements[index], elements[parent]) else { break }
      elements.swapAt(index, parent)
      index = parent
    }
  }

  mutating func pop() -> Element? {
    guard let first = elements.first else { return nil }
    let last = elements.removeLast()
    guard !elements.isEmpty else { return first }
    elements[0] = last
    var index = 0
    while index * 2 + 1 < elements.count {
      let left = index * 2 + 1
      let right = left + 1
      let best = right < elements.count && precedes(elements[right], elements[left]) ? right : left
      guard precedes(elements[best], elements[index]) else { break }
      elements.swapAt(index, best)
      index = best
    }
    return first
  }
}
