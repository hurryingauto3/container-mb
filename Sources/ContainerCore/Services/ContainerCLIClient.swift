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
    func diskUsage() async throws -> DiskUsage
    func systemState() async -> ContainerSystemState
    /// Bounded, on-demand container log read. Returns the raw text output (newline-separated
    /// lines). Never uses `--follow`; capped at `lines` (the CLI's `-n`).
    func containerLogs(id: String, lines: Int, boot: Bool) async throws -> String
    /// Lazy, on-demand `volume inspect <name>`; returns the enriched summary or nil if absent.
    func inspectVolume(name: String) async throws -> ResourceSummary?
    /// Lazy, on-demand `network inspect <name>`; returns the enriched summary or nil if absent.
    func inspectNetwork(name: String) async throws -> ResourceSummary?
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

    public func diskUsage() async throws -> DiskUsage {
        try await DiskUsageJSONMapper.diskUsage(
            from: runJSON(arguments: ["system", "df", "--format", "json"])
        )
    }

    public func containerLogs(id: String, lines: Int, boot: Bool) async throws -> String {
        var arguments = ["logs", "-n", String(lines), id]
        if boot {
            // Place `--boot` before the id: `logs --boot -n <n> <id>`.
            arguments = ["logs", "--boot", "-n", String(lines), id]
        }
        return try await runText(arguments: arguments, timeout: max(timeout, 8))
    }

    public func inspectVolume(name: String) async throws -> ResourceSummary? {
        try await ContainerJSONMapper.resources(
            from: runJSON(arguments: ["volume", "inspect", name])
        ).first
    }

    public func inspectNetwork(name: String) async throws -> ResourceSummary? {
        try await ContainerJSONMapper.resources(
            from: runJSON(arguments: ["network", "inspect", name])
        ).first
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

    // Mirrors `runJSON` but returns the raw stdout text instead of decoding JSON. Used for the
    // `logs` subcommand, whose output is plain text.
    private func runText(arguments: [String], timeout: TimeInterval? = nil) async throws -> String {
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
        return result.stdoutString
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
