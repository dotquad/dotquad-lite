//
//  MCPTools.swift
//  DotquadLite
//
//  Three tools for AI apps, answered from this Mac. Dotquad's remote MCP
//  server can't answer them: there, "my IP" is the AI app's server.
//
//  The public IP tools follow the same opt-in and the same 5-minute reuse as
//  the widget. my_local_network reads the Mac and sends nothing.
//

import Foundation
import DroppyKit

extension DotquadLiteDroplet: MCPToolProviding {
    /// No arguments: a JSON object with no properties.
    private static let noArguments = #"{"type":"object","properties":{},"additionalProperties":false}"#

    public var mcpTools: [DropletMCPTool] {
        [
            DropletMCPTool(
                name: "my_public_ip",
                title: "My public IP",
                summary: "Returns this Mac's public IP address as dotquad.app sees it: the IP, city and country it appears to be in, the network's ASN and owner, and whether it's a VPN or hosting address. Takes no arguments. Needs Dotquad Lite's lookups turned on.",
                inputSchemaJSON: Self.noArguments
            ),
            DropletMCPTool(
                name: "am_i_on_vpn",
                title: "Am I on a VPN",
                summary: "Says whether this Mac's public IP belongs to a VPN. Returns vpn (true, false or null when unknown), hosting (whether the address is in a hosting range) and the network's name. Takes no arguments. Needs Dotquad Lite's lookups turned on.",
                inputSchemaJSON: Self.noArguments
            ),
            DropletMCPTool(
                name: "my_local_network",
                title: "My local network",
                summary: "Returns this Mac's side of the network, read from the Mac without sending anything: the interface in use (for example Wi-Fi, en0), its local IPv4 and global IPv6 addresses, the router and the DNS servers. Takes no arguments. Works with lookups off.",
                inputSchemaJSON: Self.noArguments
            ),
        ]
    }

    public func performMCPTool(named name: String, argumentsJSON: String) async throws -> String {
        guard name == "my_public_ip" || name == "am_i_on_vpn" || name == "my_local_network" else {
            throw DotquadLiteToolError.unknownTool(String(name.prefix(64)))
        }
        try Self.requireNoArguments(argumentsJSON)
        if name == "my_local_network" {
            refreshLocalNetwork()
            guard let local = localNetwork else { throw ToolMessage("This Mac isn't connected to a network.") }
            return try Self.json([
                "interface": local.interface,
                "interface_kind": local.kind,
                "ipv4": local.ipv4,
                "ipv6": local.ipv6,
                "router": local.router,
                "dns": local.dns,
                "source": "this Mac",
            ])
        }
        let me: LiteMe
        do {
            me = try await currentAnswer()
        } catch let error as LiteError {
            throw ToolMessage(error.message)
        }
        let body: [String: Any?]
        if name == "my_public_ip" {
            body = [
                "ip": me.ip,
                "city": me.city,
                "country": me.country,
                "country_name": LiteText.countryName(me.country, locale: Locale(identifier: "en_US")),
                "asn": me.asn,
                "owner": me.owner,
                "vpn": me.vpn,
                "hosting": me.hosting,
                "source": "dotquad.app",
            ]
        } else {
            body = [
                "vpn": me.vpn,
                "hosting": me.hosting,
                "network": me.owner,
                "asn": me.asn,
            ]
        }
        return try Self.json(body)
    }

    private static func json(_ body: [String: Any?]) throws -> String {
        let object = body.mapValues { $0 ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Arguments come from a model and are untrusted: accept only `{}`.
    private static func requireNoArguments(_ json: String) throws {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" { return }
        guard trimmed.utf8.count <= 4096,
              let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let dictionary = object as? [String: Any],
              dictionary.isEmpty
        else { throw DotquadLiteToolError.unexpectedArguments }
    }
}

/// An error whose text is the whole message the AI app sees.
struct ToolMessage: Error, CustomStringConvertible, LocalizedError {
    let description: String
    init(_ text: String) { description = text }
    var errorDescription: String? { description }
}

extension DotquadLiteToolError: LocalizedError {
    var errorDescription: String? { description }
}
