// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ContainerCLIError: Error, LocalizedError, Equatable {
    case executableNotFound
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "container CLI not found"
        case .commandFailed(let arguments, let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "container \(arguments.joined(separator: " ")) failed with exit \(exitCode): \(detail)"
        }
    }
}

public protocol ContainerCLIClient: Sendable {
    func listContainers() async throws -> [ContainerSummary]
    func stats() async throws -> [ContainerStatsSnapshot]
    func inspectContainers(ids: [String]) async throws -> [ContainerSummary]
    func listNetworks() async throws -> [ResourceSummary]
    func listVolumes() async throws -> [ResourceSummary]
    func listImages() async throws -> [ImageSummary]
    func systemState() async -> ContainerSystemState
}

public struct ProcessContainerCLIClient: ContainerCLIClient {
    private let runner: ProcessRunning
    private let executableURL: URL?
    private let timeout: TimeInterval

    public init(
        runner: ProcessRunning = ProcessRunner(),
        executableURL: URL? = nil,
        timeout: TimeInterval = 10
    ) {
        self.runner = runner
        self.executableURL = executableURL ?? Self.locateContainerExecutable()
        self.timeout = timeout
    }

    public func listContainers() async throws -> [ContainerSummary] {
        try await ContainerJSONMapper.containers(
            from: runJSON(arguments: ["list", "--all", "--format", "json"])
        )
    }

    public func stats() async throws -> [ContainerStatsSnapshot] {
        try await ContainerJSONMapper.stats(
            from: runJSON(arguments: ["stats", "--format", "json", "--no-stream"], timeout: max(timeout, 6))
        )
    }

    public func inspectContainers(ids: [String]) async throws -> [ContainerSummary] {
        guard !ids.isEmpty else { return [] }
        return try await ContainerJSONMapper.containers(
            from: runJSON(arguments: ["inspect"] + ids)
        )
    }

    public func listNetworks() async throws -> [ResourceSummary] {
        try await ContainerJSONMapper.resources(
            from: runJSON(arguments: ["network", "list", "--format", "json"])
        )
    }

    public func listVolumes() async throws -> [ResourceSummary] {
        try await ContainerJSONMapper.resources(
            from: runJSON(arguments: ["volume", "list", "--format", "json"])
        )
    }

    public func listImages() async throws -> [ImageSummary] {
        try await ImageJSONMapper.images(
            from: runJSON(arguments: ["image", "list", "--format", "json"])
        )
    }

    public func systemState() async -> ContainerSystemState {
        guard executableURL != nil else { return .unknown }

        async let status = optionalRun(arguments: ["system", "status"], timeout: 4)
        async let version = optionalRun(arguments: ["--version"], timeout: 4)

        let statusResult = await status
        let versionResult = await version

        guard let statusResult else {
            return ContainerSystemState(
                installed: true,
                serviceRunning: false,
                version: versionResult?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines),
                message: "container system is not reachable"
            )
        }

        return ContainerJSONMapper.systemState(
            fromStatusOutput: statusResult.stdoutString,
            version: versionResult?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func runJSON(arguments: [String], timeout: TimeInterval? = nil) async throws -> Data {
        guard let executableURL else { throw ContainerCLIError.executableNotFound }
        let result = try await runner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout ?? self.timeout
        )
        guard result.exitCode == 0 else {
            throw ContainerCLIError.commandFailed(
                arguments: arguments,
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result.stdout
    }

    private func optionalRun(arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        guard let executableURL else { return nil }
        guard let result = try? await runner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout
        ) else {
            return nil
        }
        return result.exitCode == 0 ? result : nil
    }

    private static func locateContainerExecutable() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
            "/usr/bin/container",
        ]

        if let path = candidates.first(where: fileManager.isExecutableFile) {
            return URL(fileURLWithPath: path)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":").map(String.init) {
            let path = "\(directory)/container"
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}
