import ContainerCore
import Darwin
import Foundation

@main
enum SmokeTests {
    static func main() async {
        var suite = TestSuite()

        await suite.run("parses managed container shape") {
            try testParsesManagedContainerShape()
        }
        await suite.run("parses stats with missing fields") {
            try testParsesStatsWithMissingFields()
        }
        await suite.run("parses system status table") {
            try testParsesSystemStatusTable()
        }
        await suite.run("background refresh skips unchanged stats") {
            try await testBackgroundRefreshSkipsStatsWhenUnchanged()
        }
        await suite.run("refresh computes CPU percent") {
            try await testRefreshComputesCPUPercent()
        }

        suite.finish()
    }
}

private struct TestSuite {
    private var failures: [String] = []

    mutating func run(_ name: String, body: () async throws -> Void) async {
        do {
            try await body()
            print("PASS \(name)")
        } catch {
            failures.append("\(name): \(error)")
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("All smoke tests passed")
            exit(0)
        }

        print("\nFailures:")
        for failure in failures {
            print("- \(failure)")
        }
        exit(1)
    }
}

private struct ExpectationFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw ExpectationFailure(message: message)
    }
}

private func testParsesManagedContainerShape() throws {
    let data = Data(
        """
        [
          {
            "id": "abcdef1234567890",
            "configuration": {
              "id": "abcdef1234567890",
              "image": { "reference": "postgres:14.10" },
              "publishedPorts": [
                {
                  "hostAddress": "127.0.0.1",
                  "hostPort": 5437,
                  "containerPort": 5432,
                  "proto": "tcp",
                  "count": 1
                }
              ],
              "labels": { "project": "policy" },
              "networks": [{ "network": "tg-policy-service" }],
              "mounts": [
                {
                  "source": "/tmp/postgres",
                  "destination": "/var/lib/postgresql/data",
                  "readOnly": false
                }
              ],
              "initProcess": {
                "executable": "/usr/local/bin/postgres",
                "arguments": ["-D", "/data"]
              },
              "resources": {
                "cpus": 2,
                "memoryInBytes": 2147483648,
                "storage": 10737418240
              },
              "creationDate": "2026-06-23T10:00:00Z"
            },
            "status": {
              "state": "running",
              "networks": [{ "address": "192.168.64.10" }],
              "startedDate": "2026-06-23T10:01:00Z"
            }
          }
        ]
        """.utf8
    )

    let containers = try ContainerJSONMapper.containers(from: data)

    try expect(containers.count == 1, "expected one container")
    try expect(containers[0].id == "abcdef1234567890", "id mismatch")
    try expect(containers[0].shortID == "abcdef123456", "short id mismatch")
    try expect(containers[0].image == "postgres:14.10", "image mismatch")
    try expect(containers[0].state == .running, "state mismatch")
    try expect(containers[0].ports.first?.mappingDisplay == "127.0.0.1:5437 -> 5432/tcp", "port mismatch")
    try expect(containers[0].labels["project"] == "policy", "label mismatch")
    try expect(containers[0].networks == ["tg-policy-service"], "network mismatch")
    try expect(containers[0].ipAddresses == ["192.168.64.10"], "ip mismatch")
    try expect(containers[0].mounts == ["/tmp/postgres -> /var/lib/postgresql/data"], "mount mismatch")
    try expect(containers[0].command == "/usr/local/bin/postgres -D /data", "command mismatch")
    try expect(containers[0].resources.cpus == 2, "cpu limit mismatch")
    try expect(containers[0].resources.memoryBytes == 2147483648, "memory limit mismatch")
}

private func testParsesStatsWithMissingFields() throws {
    let data = Data(
        """
        [
          {
            "id": "abcdef1234567890",
            "memoryUsageBytes": 1024,
            "cpuUsageUsec": 2000000,
            "networkRxBytes": 512,
            "numProcesses": 7
          }
        ]
        """.utf8
    )

    let stats = try ContainerJSONMapper.stats(from: data)

    try expect(stats.count == 1, "expected one stats row")
    try expect(stats[0].id == "abcdef1234567890", "stats id mismatch")
    try expect(stats[0].memoryUsageBytes == 1024, "memory mismatch")
    try expect(stats[0].memoryLimitBytes == nil, "memory limit should be nil")
    try expect(stats[0].cpuUsageUsec == 2000000, "cpu mismatch")
    try expect(stats[0].cpuPercent == nil, "cpu percent should be nil")
    try expect(stats[0].networkRxBytes == 512, "network rx mismatch")
    try expect(stats[0].processCount == 7, "process count mismatch")
}

private func testParsesSystemStatusTable() throws {
    let state = ContainerJSONMapper.systemState(
        fromStatusOutput: """
        FIELD              VALUE
        status             running
        apiServer.version  1.0.0
        """,
        version: "container CLI version 1.0.0"
    )

    try expect(state.installed, "system should be installed")
    try expect(state.serviceRunning, "system should be running")
    try expect(state.version == "container CLI version 1.0.0", "version mismatch")
}

private func testBackgroundRefreshSkipsStatsWhenUnchanged() async throws {
    let client = MockContainerCLIClient()
    let coordinator = PollingCoordinator(client: client)

    _ = await coordinator.refresh(mode: .background)
    var count = await client.statsCallCount()
    try expect(count == 1, "first background refresh should collect stats")

    _ = await coordinator.refresh(mode: .background)
    count = await client.statsCallCount()
    try expect(count == 1, "second unchanged background refresh should skip stats")

    _ = await coordinator.refresh(mode: .foreground)
    count = await client.statsCallCount()
    try expect(count == 2, "foreground refresh should collect stats")
}

private func testRefreshComputesCPUPercent() async throws {
    let client = MockContainerCLIClient()
    let coordinator = PollingCoordinator(client: client)

    _ = await coordinator.refresh(mode: .foreground)
    let snapshot = await coordinator.refresh(mode: .foreground)

    let cpuPercent = snapshot.statsByID["abcdef1234567890"]?.cpuPercent
    try expect(cpuPercent != nil, "cpu percent should be computed")
    try expect((cpuPercent ?? 0) > 0, "cpu percent should be greater than zero")
}

private actor MockContainerCLIClient: ContainerCLIClient {
    private var statsCalls = 0

    func listContainers() async throws -> [ContainerSummary] {
        [
            ContainerSummary(
                id: "abcdef1234567890",
                image: "postgres:14.10",
                state: .running,
                raw: .object(["id": .string("abcdef1234567890")])
            )
        ]
    }

    func stats() async throws -> [ContainerStatsSnapshot] {
        statsCalls += 1
        return [
            ContainerStatsSnapshot(
                id: "abcdef1234567890",
                memoryUsageBytes: 1024,
                memoryLimitBytes: 2048,
                cpuUsageUsec: UInt64(statsCalls * 1_000_000),
                processCount: 3
            )
        ]
    }

    func inspectContainers(ids: [String]) async throws -> [ContainerSummary] {
        try await listContainers().filter { ids.contains($0.id) }
    }

    func listNetworks() async throws -> [ResourceSummary] {
        [ResourceSummary(id: "default", name: "default", detail: "192.168.64.0/24")]
    }

    func listVolumes() async throws -> [ResourceSummary] {
        [ResourceSummary(id: "postgres", name: "postgres")]
    }

    func systemState() async -> ContainerSystemState {
        ContainerSystemState(installed: true, serviceRunning: true, version: "1.0.0")
    }

    func statsCallCount() -> Int {
        statsCalls
    }
}
