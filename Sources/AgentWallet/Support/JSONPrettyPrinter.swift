import Foundation

enum JSONPrettyPrinter {
    static func parse(_ string: String) -> Any? {
        guard let data = string.data(using: .utf8), !data.isEmpty else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data)
    }

    static func prettyString(_ object: Any?) -> String? {
        guard let object,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func compactSummary(_ object: Any?) -> String? {
        if let dictionary = object as? [String: Any] {
            return dictionary.keys.sorted().prefix(8).joined(separator: ", ")
        }

        if let array = object as? [Any] {
            return "\(array.count) 条记录"
        }

        return nil
    }

    static func dictionary(_ object: Any?, path: [String] = []) -> [String: Any]? {
        guard !path.isEmpty else {
            return object as? [String: Any]
        }

        var current = object
        for component in path {
            current = (current as? [String: Any])?[component]
        }

        return current as? [String: Any]
    }

    static func array(_ object: Any?, path: [String] = []) -> [Any] {
        if path.isEmpty {
            return object as? [Any] ?? []
        }

        var current = object
        for component in path {
            current = (current as? [String: Any])?[component]
        }

        return current as? [Any] ?? []
    }

    static func stringValue(_ object: Any?, path: [String]) -> String? {
        var current = object
        for component in path {
            current = (current as? [String: Any])?[component]
        }

        return current as? String
    }

    static func formatCurrency(_ value: Any?) -> String {
        guard let number = doubleValue(value) else {
            return "$0.00"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = number >= 1_000 ? 0 : 2
        return formatter.string(from: NSNumber(value: number)) ?? "$\(number)"
    }

    static func formatPercent(_ value: Any?) -> String {
        guard let number = doubleValue(value) else {
            return "-"
        }

        return String(format: "%.2f%%", number)
    }

    static func formatNumber(_ value: Any?) -> String {
        guard let number = doubleValue(value) else {
            return "-"
        }

        if number < 0.0001 {
            return String(format: "%.8f", number)
        }

        if number < 1 {
            return String(format: "%.5f", number)
        }

        return String(format: "%.2f", number)
    }

    static func shortAddress(_ value: String) -> String {
        guard value.count > 12 else {
            return value.isEmpty ? "-" : value
        }

        return "\(value.prefix(6))...\(value.suffix(4))"
    }

    static func shortHash(_ value: String) -> String {
        shortAddress(value)
    }

    static func weiHexToETH(_ value: String?) -> String {
        guard let integer = hexToDecimal(value) else {
            return "-"
        }

        let eth = Double(truncating: integer) / 1_000_000_000_000_000_000
        return String(format: "%.8f ETH", eth)
    }

    static func weiHexToGwei(_ value: String?) -> String {
        guard let integer = hexToDecimal(value) else {
            return "-"
        }

        let gwei = Double(truncating: integer) / 1_000_000_000
        return String(format: "%.5f gwei", gwei)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let string as String:
            return Double(string)
        case let number as NSNumber:
            return number.doubleValue
        default:
            return nil
        }
    }

    private static func hexToDecimal(_ value: String?) -> NSDecimalNumber? {
        guard var hex = value?.lowercased(), !hex.isEmpty else {
            return nil
        }

        if hex.hasPrefix("0x") {
            hex.removeFirst(2)
        }

        var result = Decimal(0)
        for character in hex {
            guard let digit = Int(String(character), radix: 16) else {
                return nil
            }
            result *= 16
            result += Decimal(digit)
        }

        return NSDecimalNumber(decimal: result)
    }
}
