import Foundation

/// Mirrors Microsoft Graph `emailAddress`.
public struct EmailAddress: Codable, Hashable, Sendable {
    public var name: String?
    public var address: String?

    public init(name: String? = nil, address: String? = nil) {
        self.name = name
        self.address = address
    }
}

/// Mirrors Microsoft Graph `recipient`.
public struct Recipient: Codable, Hashable, Sendable {
    public var emailAddress: EmailAddress

    public init(emailAddress: EmailAddress) {
        self.emailAddress = emailAddress
    }

    public init(address: String, name: String? = nil) {
        self.emailAddress = EmailAddress(name: name, address: address)
    }
}

/// Mirrors Microsoft Graph `sizeRange`. Sizes are in **kilobytes**
/// (the neutral ``SizeConstraint`` is in bytes; ``GraphRuleMapper`` converts).
public struct SizeRange: Codable, Hashable, Sendable {
    public var minimumSize: Int?
    public var maximumSize: Int?

    public init(minimumSize: Int? = nil, maximumSize: Int? = nil) {
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
    }
}
