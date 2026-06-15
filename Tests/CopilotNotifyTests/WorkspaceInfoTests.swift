import Testing
import Foundation
@testable import CopilotNotifyLib

@Suite("WorkspaceInfo Tests")
struct WorkspaceInfoTests {
    
    @Test("Parse valid workspace.yaml")
    func parseValid() throws {
        let tmpFile = NSTemporaryDirectory() + "test-workspace-\(UUID().uuidString).yaml"
        let content = """
        id: abc123-def456
        cwd: /Users/test/project
        summary: Fix Login Bug
        updated_at: 2026-06-11T10:00:00.123Z
        remote_steerable: false
        """
        try content.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        
        let info = WorkspaceInfo.parse(from: tmpFile)
        #expect(info != nil)
        #expect(info?.id == "abc123-def456")
        #expect(info?.summary == "Fix Login Bug")
        #expect(info?.cwd == "/Users/test/project")
        #expect(info?.updatedAt != nil)
    }
    
    @Test("Parse minimal workspace with just id")
    func parseMinimal() throws {
        let tmpFile = NSTemporaryDirectory() + "test-workspace-\(UUID().uuidString).yaml"
        let content = "id: session-123\n"
        try content.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        
        let info = WorkspaceInfo.parse(from: tmpFile)
        #expect(info != nil)
        #expect(info?.id == "session-123")
        #expect(info?.summary == "Untitled Session")
        #expect(info?.cwd == nil)
    }
    
    @Test("Returns nil when no id present")
    func parseNoId() throws {
        let tmpFile = NSTemporaryDirectory() + "test-workspace-\(UUID().uuidString).yaml"
        let content = "summary: Something\ncwd: /tmp\n"
        try content.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        
        let info = WorkspaceInfo.parse(from: tmpFile)
        #expect(info == nil)
    }
    
    @Test("Returns nil for nonexistent file")
    func parseNonexistent() {
        let info = WorkspaceInfo.parse(from: "/nonexistent/workspace.yaml")
        #expect(info == nil)
    }
    
    @Test("Handles colons in summary value")
    func parseSummaryWithColons() throws {
        let tmpFile = NSTemporaryDirectory() + "test-workspace-\(UUID().uuidString).yaml"
        let content = "id: sess-1\nsummary: Fix: Handle edge case\n"
        try content.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        
        let info = WorkspaceInfo.parse(from: tmpFile)
        #expect(info?.summary == "Fix: Handle edge case")
    }
}
