// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ContainerJSONMapper {
    private static let decoder = JSONDecoder()
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let fallbackISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func containers(from data: Data) throws -> [ContainerSummary] {
        let items = try rootArray(from: data)
        return items.compactMap(container(from:))
    }

    public static func stats(from data: Data) throws -> [ContainerStatsSnapshot] {
        let items = try rootArray(from: data)
        return items.compactMap(stats(from:))
    }

    public static func resources(from data: Data) throws -> [ResourceSummary] {
        let items = try rootArray(from: data)
        return items.enumerated().map { index, item in
            let object = item.objectValue ?? [:]
            let id = object["id"]?.stringValue
                ?? object["name"]?.stringValue
                ?? item.value(at: ["configuration", "id"])?.stringValue
                ?? "resource-\(index)"
            let name = object["name"]?.stringValue
                ?? item.value(at: ["configuration", "name"])?.stringValue
                ?? id
            return ResourceSummary(
                id: id,
                name: name,
                detail: resourceDetail(from: item, object: object),
                attributes: resourceAttributes(from: item)
            )
        }
    }

    public static func systemState(fromStatusOutput output: String, version: String?) -> ContainerSystemState {
        let running = output
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let normalized = line.lowercased()
                return normalized.contains("status") && normalized.contains("running")
            }

        let message = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return ContainerSystemState(
            installed: true,
            serviceRunning: running,
            version: version,
            message: running ? nil : message
        )
    }

    private static func rootArray(from data: Data) throws -> [JSONValue] {
        guard !data.trimmedString.isEmpty else { return [] }
        let value = try decoder.decode(JSONValue.self, from: data)
        guard let array = value.arrayValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Expected top-level JSON array")
            )
        }
        return array
    }

    private static func container(from value: JSONValue) -> ContainerSummary? {
        guard let object = value.objectValue else { return nil }
        let configuration = object["configuration"]?.objectValue ?? object
        let statusObject = object["status"]?.objectValue
        let stateValue = statusObject?["state"]?.stringValue ?? object["status"]?.stringValue

        let id = object["id"]?.stringValue
            ?? configuration["id"]?.stringValue
            ?? value.deepValues(named: "id").compactMap(\.stringValue).first
        guard let id, !id.isEmpty else { return nil }

        return ContainerSummary(
            id: id,
            image: imageName(from: configuration["image"]) ?? "--",
            state: ContainerRuntimeState(rawStatus: stateValue),
            createdAt: date(from: configuration["creationDate"]),
            startedAt: date(from: statusObject?["startedDate"] ?? object["startedDate"]),
            ipAddresses: ipAddresses(from: value),
            ports: ports(from: configuration["publishedPorts"]),
            labels: labels(from: configuration["labels"]),
            mounts: mounts(from: configuration["mounts"]),
            networks: networks(from: configuration["networks"], statusNetworks: statusObject?["networks"]),
            command: command(from: configuration["initProcess"]),
            resources: resources(from: configuration["resources"]),
            raw: value
        )
    }

    private static func stats(from value: JSONValue) -> ContainerStatsSnapshot? {
        guard let object = value.objectValue else { return nil }
        guard let id = object["id"]?.stringValue else { return nil }

        let cpuPercent = object["cpuPercent"]?.doubleValue
            ?? object["cpuPercentage"]?.doubleValue
            ?? object["cpu"]?.doubleValue

        return ContainerStatsSnapshot(
            id: id,
            memoryUsageBytes: object["memoryUsageBytes"]?.uint64Value,
            memoryLimitBytes: object["memoryLimitBytes"]?.uint64Value,
            cpuUsageUsec: object["cpuUsageUsec"]?.uint64Value,
            cpuPercent: cpuPercent,
            networkRxBytes: object["networkRxBytes"]?.uint64Value,
            networkTxBytes: object["networkTxBytes"]?.uint64Value,
            blockReadBytes: object["blockReadBytes"]?.uint64Value,
            blockWriteBytes: object["blockWriteBytes"]?.uint64Value,
            processCount: object["numProcesses"]?.uint64Value ?? object["processCount"]?.uint64Value
        )
    }

    private static func imageName(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = value.stringValue {
            return string
        }

        let directKeys = ["reference", "name", "tag", "digest"]
        for key in directKeys {
            if let string = value[key]?.stringValue, !string.isEmpty {
                return string
            }
        }

        for key in directKeys {
            if let string = value.deepValues(named: key).compactMap(\.stringValue).first(where: { !$0.isEmpty }) {
                return string
            }
        }

        return nil
    }

    private static func ports(from value: JSONValue?) -> [ContainerPort] {
        guard let items = value?.arrayValue else { return [] }
        return items.compactMap { item in
            guard let object = item.objectValue else { return nil }
            let hostPort = uint16(from: object["hostPort"])
            let containerPort = uint16(from: object["containerPort"])
            let proto = object["proto"]?.stringValue
                ?? object["protocol"]?.stringValue
                ?? "tcp"
            let address = object["hostAddress"]?.stringValue
                ?? object["hostIP"]?.stringValue
                ?? object["ip"]?.stringValue
                ?? "localhost"
            let count = uint16(from: object["count"]) ?? 1
            return ContainerPort(
                hostAddress: address,
                hostPort: hostPort,
                containerPort: containerPort,
                protocolName: proto.lowercased(),
                count: count
            )
        }
    }

    private static func labels(from value: JSONValue?) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        return object.reduce(into: [:]) { labels, entry in
            if let string = entry.value.stringValue {
                labels[entry.key] = string
            }
        }
    }

    private static func mounts(from value: JSONValue?) -> [String] {
        guard let items = value?.arrayValue else { return [] }
        return items.compactMap { item in
            guard let object = item.objectValue else { return item.stringValue }
            let source = object["source"]?.stringValue
                ?? object["hostPath"]?.stringValue
                ?? object["volume"]?.stringValue
                ?? object["name"]?.stringValue
            let destination = object["destination"]?.stringValue
                ?? object["mountpoint"]?.stringValue
                ?? object["path"]?.stringValue
            let readOnly = object["readOnly"]?.stringValue == "true" ? " ro" : ""

            switch (source, destination) {
            case let (source?, destination?):
                return "\(source) -> \(destination)\(readOnly)"
            case let (source?, nil):
                return source
            case let (nil, destination?):
                return destination
            default:
                return nil
            }
        }
    }

    private static func networks(from configNetworks: JSONValue?, statusNetworks: JSONValue?) -> [String] {
        let values = [configNetworks, statusNetworks]
            .compactMap { $0?.arrayValue }
            .flatMap { $0 }

        let names = values.compactMap { item -> String? in
            if let string = item.stringValue {
                return string
            }
            return item["network"]?.stringValue
                ?? item["name"]?.stringValue
                ?? item["id"]?.stringValue
        }

        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    // Networks expose the subnet under status; volumes expose source/driver under configuration.
    // Extracts the human-readable fields shown for volumes and networks. The same `resources`
    // endpoint shape backs both, so we probe the union of known keys and keep whatever is present:
    // volumes carry driver/format/size/source, networks carry mode/subnet/gateway/plugin.
    private static func resourceAttributes(from item: JSONValue) -> [ResourceAttribute] {
        var attributes: [ResourceAttribute] = []

        func add(_ label: String, paths: [[String]], transform: (JSONValue) -> String? = { $0.stringValue }) {
            for path in paths {
                guard let value = item.value(at: path), let formatted = transform(value), !formatted.isEmpty else {
                    continue
                }
                attributes.append(ResourceAttribute(label: label, value: formatted))
                return
            }
        }

        // Volume fields.
        add("Driver", paths: [["driver"], ["configuration", "driver"]])
        add("Format", paths: [["format"], ["configuration", "format"]])
        add("Size", paths: [["sizeInBytes"], ["configuration", "sizeInBytes"]]) { value in
            value.uint64Value.map(DisplayFormatters.bytes)
        }
        add("Source", paths: [["source"], ["configuration", "source"], ["path"]])

        // Network fields.
        add("Mode", paths: [["mode"], ["configuration", "mode"]])
        add("Subnet", paths: [["subnet"], ["status", "ipv4Subnet"], ["configuration", "subnet"]])
        add("Gateway", paths: [["gateway"], ["status", "ipv4Gateway"]])
        add("Plugin", paths: [["plugin"], ["configuration", "plugin"]])

        // Inspect-only fields. These keys are absent from `list` output (which is why the existing
        // `testParsesLiveResourceDetail` list assertions stay stable) and only appear when the
        // richer `volume inspect`/`network inspect` shapes are mapped, so they are purely additive.
        add("IPv6 Subnet", paths: [["status", "ipv6Subnet"]])
        add("Created", paths: [["creationDate"], ["configuration", "creationDate"]])
        addObjectEntries("Label", paths: [["labels"], ["configuration", "labels"]])
        addObjectEntries("Option", paths: [["options"], ["configuration", "options"]])

        return attributes

        // Appends one attribute per key in the first non-empty object found at `paths`, sorted by
        // key for deterministic ordering. Empty objects (the common case in list output) add nothing.
        func addObjectEntries(_ prefix: String, paths: [[String]]) {
            for path in paths {
                guard let object = item.value(at: path)?.objectValue, !object.isEmpty else { continue }
                for key in object.keys.sorted() {
                    guard let value = object[key]?.stringValue, !value.isEmpty else { continue }
                    attributes.append(ResourceAttribute(label: "\(prefix): \(key)", value: value))
                }
                return
            }
        }
    }

    private static func resourceDetail(from item: JSONValue, object: [String: JSONValue]) -> String? {
        // Precedence mirrors `resourceAttributes` so the one-line detail never disagrees with the
        // richer attribute list when both a top-level and a nested key are present.
        let candidates: [JSONValue?] = [
            object["subnet"],
            item.value(at: ["status", "ipv4Subnet"]),
            object["source"],
            item.value(at: ["configuration", "source"]),
            object["path"],
            object["driver"],
            item.value(at: ["configuration", "driver"]),
        ]
        return candidates.lazy.compactMap { $0?.stringValue }.first
    }

    private static func ipAddresses(from value: JSONValue) -> [String] {
        let candidates = ["ipAddress", "ipv4Address", "ipv6Address", "address", "ip"]
            .flatMap { key in value.deepValues(named: key).compactMap(\.stringValue) }
            // The CLI reports addresses in CIDR form (e.g. "192.168.64.2/24"); drop the prefix length.
            .map { String($0.prefix(while: { $0 != "/" })) }
            .filter { candidate in
                candidate.contains(".") || candidate.contains(":")
            }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private static func command(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        let executable = value["executable"]?.stringValue
            ?? value["path"]?.stringValue
            ?? value["command"]?.stringValue
        let arguments = value["arguments"]?.arrayValue?.compactMap(\.stringValue)
            ?? value["args"]?.arrayValue?.compactMap(\.stringValue)
            ?? []

        if let executable, !executable.isEmpty {
            return ([executable] + arguments).joined(separator: " ")
        }
        return arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }

    private static func resources(from value: JSONValue?) -> ResourceLimit {
        guard let object = value?.objectValue else { return ResourceLimit() }
        return ResourceLimit(
            cpus: object["cpus"]?.intValue,
            memoryBytes: object["memoryInBytes"]?.uint64Value ?? object["memory"]?.uint64Value,
            storageBytes: object["storage"]?.uint64Value
        )
    }

    private static func uint16(from value: JSONValue?) -> UInt16? {
        guard let number = value?.uint64Value, number <= UInt64(UInt16.max) else { return nil }
        return UInt16(number)
    }

    private static func date(from value: JSONValue?) -> Date? {
        guard let value else { return nil }
        if let string = value.stringValue {
            return isoFormatter.date(from: string)
                ?? fallbackISOFormatter.date(from: string)
                ?? Double(string).map(Date.init(timeIntervalSince1970:))
        }

        if let seconds = value.doubleValue {
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }
}

private extension Data {
    var trimmedString: String {
        String(data: self, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
