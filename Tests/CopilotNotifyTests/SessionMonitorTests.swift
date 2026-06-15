import Testing
import Foundation
@testable import CopilotNotifyLib

@Suite("SessionMonitor Tests")
struct SessionMonitorTests {
    
    private func makeTmpDir() -> String {
        let dir = NSTemporaryDirectory() + "copilot-notify-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }
    
    @Test("Scan detects completed session")
    func scanDetectsCompletion() throws {
        let tmpDir = makeTmpDir()
        defer { cleanup(tmpDir) }
        
        let sessionId = "test-session-001"
        let sessionDir = "\(tmpDir)/\(sessionId)"
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        
        try "id: \(sessionId)\nsummary: Build Feature X\n"
            .write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)
        
        try """
        {"type":"user.message","timestamp":"2026-06-11T10:00:00Z","data":{}}
        {"type":"assistant.message","timestamp":"2026-06-11T10:01:00Z","data":{"content":"Working..."}}
        {"type":"session.task_complete","timestamp":"2026-06-11T10:05:00Z","data":{"summary":"Done"}}
        """.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        
        let monitor = SessionMonitor(pollInterval: 60, sessionStatePath: tmpDir)
        monitor.scan()
        
        #expect(monitor.alerts.count == 1)
        #expect(monitor.alerts[sessionId]?.alertType == .completion)
        #expect(monitor.alerts[sessionId]?.summary == "Build Feature X")
    }
    
    @Test("Scan detects question session")
    func scanDetectsQuestion() throws {
        let tmpDir = makeTmpDir()
        defer { cleanup(tmpDir) }
        
        let sessionId = "test-session-002"
        let sessionDir = "\(tmpDir)/\(sessionId)"
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        
        try "id: \(sessionId)\nsummary: Review PR\n"
            .write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)
        
        try """
        {"type":"user.message","timestamp":"2026-06-11T10:00:00Z","data":{}}
        {"type":"assistant.message","timestamp":"2026-06-11T10:01:00Z","data":{"content":"I used ask_user to check"}}
        {"type":"assistant.turn_end","timestamp":"2026-06-11T10:01:01Z","data":{"turnId":"1"}}
        """.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        
        let monitor = SessionMonitor(pollInterval: 60, sessionStatePath: tmpDir)
        monitor.scan()
        
        #expect(monitor.alerts.count == 1)
        #expect(monitor.alerts[sessionId]?.alertType == .question)
    }
    
    @Test("Scan auto-dismisses when user responds")
    func scanAutoDismisses() throws {
        let tmpDir = makeTmpDir()
        defer { cleanup(tmpDir) }
        
        let sessionId = "test-session-003"
        let sessionDir = "\(tmpDir)/\(sessionId)"
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        
        try "id: \(sessionId)\nsummary: Task\n"
            .write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)
        
        // Session is waiting
        let events1 = """
        {"type":"user.message","timestamp":"2026-06-11T10:00:00Z","data":{}}
        {"type":"assistant.message","timestamp":"2026-06-11T10:01:00Z","data":{"content":"question"}}
        {"type":"assistant.turn_end","timestamp":"2026-06-11T10:01:01Z","data":{"turnId":"1"}}
        """
        try events1.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        
        let monitor = SessionMonitor(pollInterval: 60, sessionStatePath: tmpDir)
        monitor.scan()
        #expect(monitor.alerts.count == 1)
        
        // User responds
        let events2 = events1 + "\n{\"type\":\"user.message\",\"timestamp\":\"2026-06-11T10:02:00Z\",\"data\":{}}\n"
        // Small delay to ensure file mod time changes
        Thread.sleep(forTimeInterval: 0.1)
        try events2.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        
        monitor.scan()
        #expect(monitor.alerts.count == 0)
    }
    
    @Test("Dismiss removes alert manually")
    func dismissRemovesAlert() throws {
        let tmpDir = makeTmpDir()
        defer { cleanup(tmpDir) }
        
        let sessionId = "test-session-004"
        let sessionDir = "\(tmpDir)/\(sessionId)"
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        
        try "id: \(sessionId)\nsummary: Task\n"
            .write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)
        
        try """
        {"type":"user.message","timestamp":"2026-06-11T10:00:00Z","data":{}}
        {"type":"session.task_complete","timestamp":"2026-06-11T10:05:00Z","data":{}}
        """.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        
        let monitor = SessionMonitor(pollInterval: 60, sessionStatePath: tmpDir)
        monitor.scan()
        #expect(monitor.alerts.count == 1)
        
        monitor.dismiss(sessionId: sessionId)
        #expect(monitor.alerts.count == 0)
    }
    
    @Test("Scan ignores old sessions")
    func scanIgnoresOldSessions() throws {
        let tmpDir = makeTmpDir()
        defer { cleanup(tmpDir) }
        
        let sessionId = "test-session-old"
        let sessionDir = "\(tmpDir)/\(sessionId)"
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        
        try """
        {"type":"session.task_complete","timestamp":"2024-01-01T10:00:00Z","data":{}}
        """.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        
        // Set modification date to 2 days ago
        let oldDate = Date().addingTimeInterval(-172800)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: "\(sessionDir)/events.jsonl"
        )
        
        let monitor = SessionMonitor(pollInterval: 60, sessionStatePath: tmpDir)
        monitor.scan()
        #expect(monitor.alerts.count == 0)
    }
    
    @Test("onAlertsChanged callback fires on change")
    func callbackFires() throws {
        let tmpDir = makeTmpDir()
        defer { cleanup(tmpDir) }
        
        let sessionId = "test-session-callback"
        let sessionDir = "\(tmpDir)/\(sessionId)"
        try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        
        try "id: \(sessionId)\nsummary: Callback Test\n"
            .write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)
        
        try """
        {"type":"user.message","timestamp":"2026-06-11T10:00:00Z","data":{}}
        {"type":"session.task_complete","timestamp":"2026-06-11T10:05:00Z","data":{}}
        """.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        
        let monitor = SessionMonitor(pollInterval: 60, sessionStatePath: tmpDir)
        
        var callbackAlerts: [SessionAlert]?
        monitor.onAlertsChanged = { alerts in
            callbackAlerts = alerts
        }
        
        monitor.scan()
        #expect(callbackAlerts != nil)
        #expect(callbackAlerts?.count == 1)
    }
    
    @Test("Multiple sessions detected simultaneously")
    func multipleSessions() throws {
        let tmpDir = makeTmpDir()
        defer { cleanup(tmpDir) }
        
        for i in 1...3 {
            let sessionId = "multi-session-\(i)"
            let sessionDir = "\(tmpDir)/\(sessionId)"
            try FileManager.default.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
            
            try "id: \(sessionId)\nsummary: Task \(i)\n"
                .write(toFile: "\(sessionDir)/workspace.yaml", atomically: true, encoding: .utf8)
            
            try """
            {"type":"user.message","timestamp":"2026-06-11T10:00:00Z","data":{}}
            {"type":"session.task_complete","timestamp":"2026-06-11T10:05:00Z","data":{}}
            """.write(toFile: "\(sessionDir)/events.jsonl", atomically: true, encoding: .utf8)
        }
        
        let monitor = SessionMonitor(pollInterval: 60, sessionStatePath: tmpDir)
        monitor.scan()
        #expect(monitor.alerts.count == 3)
    }
}
