import AppKit
import Foundation
import SwiftUI

enum ChatBubbleAttributedString {
    static func build(_ text: String, accent: Color = AppTheme.accent) -> AttributedString {
        var attributed = AttributedString(text)

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return attributed
        }

        let nsText = text as NSString
        let matches = detector.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let attrRange = attributed.range(of: String(text[range])) else {
                continue
            }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = accent
            attributed[attrRange].underlineStyle = .single
        }

        return attributed
    }
}
