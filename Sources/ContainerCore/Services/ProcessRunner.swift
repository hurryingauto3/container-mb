// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    public var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

public enum CommandRunnerError: Error, LocalizedError, Equatable {
    case timedOut(executable: String, arguments: [String], timeout: TimeInterval)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let executable, let arguments, let timeout):
            return "Command timed out after \(timeout)s: \(([executable] + arguments).joined(separator: " "))"
        case .launchFailed(let message):
            return message
        }
    }
}

public protocol ProcessRunning: Sendable {
    func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandResult
}

public final class ProcessRunner: ProcessRunning, @unchecked Sendable {
    public init() {}

    public func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(
                        returning: try Self.runBlocking(
                            executableURL: executableURL,
                            arguments: arguments,
                            timeout: timeout
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let finished = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed(error.localizedDescription)
        }

        let waitResult = finished.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw CommandRunnerError.timedOut(
                executable: executableURL.path,
                arguments: arguments,
                timeout: timeout
            )
        }

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}
