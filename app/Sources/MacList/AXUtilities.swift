import ApplicationServices
import Foundation

enum AXAccess {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute) as? NSNumber)?.boolValue
    }

    static func url(_ element: AXUIElement, _ attribute: String) -> URL? {
        if let url = value(element, attribute) as? URL { return url }
        if let string = value(element, attribute) as? String {
            if let url = URL(string: string), url.isFileURL { return url }
            if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
        }
        return nil
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = value(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint,
              AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = value(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize,
              AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    static func rawFrame(_ element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute),
              let size = size(element, kAXSizeAttribute),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    @discardableResult
    static func setValue(
        _ value: CFTypeRef,
        on element: AXUIElement,
        attribute: String
    ) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    static func supportsPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String] else {
            return false
        }
        return actions.contains(kAXPressAction as String)
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    static func isSame(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }

    static func descendants(
        of root: AXUIElement,
        maxNodes: Int = 1_200
    ) -> [AXUIElement] {
        var queue = elements(root, kAXChildrenAttribute)
        var result: [AXUIElement] = []
        var seen = Set<CFHashCode>()

        while !queue.isEmpty, result.count < maxNodes {
            let element = queue.removeFirst()
            let hash = CFHash(element)
            guard seen.insert(hash).inserted else { continue }
            result.append(element)
            queue.append(contentsOf: elements(element, kAXChildrenAttribute))
        }
        return result
    }

    static func nearestAncestor(
        from element: AXUIElement,
        matching roles: Set<String>,
        maxDepth: Int = 16
    ) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<maxDepth {
            guard let candidate = current else { return nil }
            if let role = string(candidate, kAXRoleAttribute), roles.contains(role) {
                return candidate
            }
            current = self.element(candidate, kAXParentAttribute)
        }
        return nil
    }

    static func topLevelElement(for element: AXUIElement) -> AXUIElement? {
        self.element(element, kAXTopLevelUIElementAttribute)
            ?? nearestAncestor(
                from: element,
                matching: [kAXSheetRole as String, kAXWindowRole as String]
            )
    }

    static func isAncestor(
        _ ancestor: AXUIElement,
        of element: AXUIElement,
        maxDepth: Int = 20
    ) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<maxDepth {
            guard let candidate = current else { return false }
            if isSame(candidate, ancestor) { return true }
            current = self.element(candidate, kAXParentAttribute)
        }
        return false
    }
}
