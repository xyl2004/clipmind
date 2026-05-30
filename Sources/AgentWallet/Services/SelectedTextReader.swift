import AppKit
import ApplicationServices

enum SelectedTextReader {
    static func readSelectedText(promptForPermission: Bool = true) -> SelectedTextCapture {
        if let context = readViaAccessibility(promptForPermission: promptForPermission) {
            return .success(context.text, source: .accessibility, sourceRect: context.sourceRect)
        }

        if let text = copySelectionFallback() {
            return .success(text, source: .clipboardFallback, sourceRect: nil)
        }

        if !AXIsProcessTrusted() {
            return .failure("需要在系统设置里允许 AgentWallet 使用“辅助功能”，才能读取其他应用里的选中文字。")
        }

        return .failure("没有读取到选中文字，已保留当前输入内容。")
    }

    private static func readViaAccessibility(promptForPermission: Bool) -> SelectionReadContext? {
        if promptForPermission {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusStatus == .success, let focusedElement else {
            return nil
        }

        let element = focusedElement as! AXUIElement
        let range = selectedTextRange(in: element)
        guard let text = selectedText(in: element, range: range) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return SelectionReadContext(
            text: trimmed,
            sourceRect: range.flatMap { selectedBounds(in: element, range: $0) }
        )
    }

    private static func selectedText(in element: AXUIElement, range: CFRange?) -> String? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success,
           let text = value as? String,
           !text.isEmpty {
            return text
        }

        guard var copiedRange = range,
              let rangeValue = AXValueCreate(.cfRange, &copiedRange) else {
            return nil
        }

        var parameterizedValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &parameterizedValue
        )
        guard result == .success else {
            return nil
        }

        return parameterizedValue as? String
    }

    private static func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.length > 0 else {
            return nil
        }

        return range
    }

    private static func selectedBounds(in element: AXUIElement, range: CFRange) -> CGRect? {
        var copiedRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &copiedRange) else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }

        return ScreenGeometry.normalizedAccessibilityRect(rect)
    }

    private static func copySelectionFallback() -> String? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        let changeCount = pasteboard.changeCount

        sendCommandC()

        let deadline = Date().addingTimeInterval(0.7)
        var copiedText: String?
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            if pasteboard.changeCount != changeCount,
               let text = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                copiedText = text
                break
            }
        }

        snapshot.restore(to: pasteboard)
        return copiedText
    }

    private static func sendCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeForC: CGKeyCode = 8

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForC, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForC, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum SelectedTextCapture {
    case success(String, source: SelectedTextSource, sourceRect: CGRect?)
    case failure(String)
}

enum SelectedTextSource {
    case accessibility
    case clipboardFallback

    var label: String {
        switch self {
        case .accessibility:
            "已读取当前选中文字。"
        case .clipboardFallback:
            "已通过复制回退读取当前选中文字。"
        }
    }
}

private struct SelectionReadContext {
    let text: String
    let sourceRect: CGRect?
}

private struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let capturedItems: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            let itemData: [NSPasteboard.PasteboardType: Data] = Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type, data)
            })
            return itemData
        } ?? []

        return ClipboardSnapshot(items: capturedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else {
            return
        }

        let restoredItems = items.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
