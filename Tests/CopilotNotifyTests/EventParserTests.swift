import Testing
import Foundation
@testable import CopilotNotifyLib

@Suite("EventParser Tests")
struct EventParserTests {
    
    // MARK: - parseDate
    
    @Test("Parse ISO date with fractional seconds")
    func parseDateWithFractionalSeconds() {
        let date = EventParser.parseDate("2026-06-11T20:20:30.895Z")
        #expect(date != nil)
    }
    
    @Test("Parse ISO date without fractional seconds")
    func parseDateWithoutFractionalSeconds() {
        let date = EventParser.parseDate("2026-06-11T20:20:30Z")
        #expect(date != nil)
    }
    
    @Test("Parse invalid date returns nil")
    func parseDateInvalid() {
        let date = EventParser.parseDate("not-a-date")
        #expect(date == nil)
    }
    
    // MARK: - readEvents from file
    
    @Test("Read events from a jsonl file")
    func readEventsFromFile() throws {
        let tmpFile = NSTemporaryDirectory() + "test-events-\(UUID().uuidString).jsonl"
        let content = """
        {"type":"session.start","timestamp":"2026-06-11T10:00:00Z","data":{}}
        {"type":"user.message","timestamp":"2026-06-11T10:00:01Z","data":{"content":"hello"}}
        {"type":"assistant.message","timestamp":"2026-06-11T10:00:05Z","data":{"content":"hi there"}}
        {"type":"assistant.turn_end","timestamp":"2026-06-11T10:00:06Z","data":{"turnId":"0"}}
        """
        try content.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        
        let (events, offset) = EventParser.readEvents(from: tmpFile)
        #expect(events.count == 4)
        #expect(events[0].type == "session.start")
        #expect(events[3].type == "assistant.turn_end")
        #expect(offset > 0)
    }
    
    @Test("Read events from offset skips earlier content")
    func readEventsFromOffset() throws {
        let tmpFile = NSTemporaryDirectory() + "test-events-\(UUID().uuidString).jsonl"
        let line1 = "{\"type\":\"session.start\",\"timestamp\":\"2026-06-11T10:00:00Z\",\"data\":{}}\n"
        let line2 = "{\"type\":\"user.message\",\"timestamp\":\"2026-06-11T10:00:01Z\",\"data\":{}}\n"
        try (line1 + line2).write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }
        
        let offset = UInt64(line1.utf8.count)
        let (events, _) = EventParser.readEvents(from: tmpFile, afterOffset: offset)
        #expect(events.count == 1)
        #expect(events[0].type == "user.message")
    }
    
    @Test("Read events from nonexistent file returns empty")
    func readEventsNonexistentFile() {
        let (events, offset) = EventParser.readEvents(from: "/nonexistent/path.jsonl")
        #expect(events.count == 0)
        #expect(offset == 0)
    }
    
    // MARK: - detectAlert
    
    @Test("Detect completion alert")
    func detectAlertCompletion() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:05:00Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.message", timestamp: t2),
            .init(type: "session.task_complete", timestamp: t3, data: ["summary": "Done"]),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result != nil)
        #expect(result?.type == .completion)
        #expect(result?.since == t3)
    }
    
    @Test("Detect question alert from ask_user")
    func detectAlertQuestion() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:01:01Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.message", timestamp: t2, data: ["content": "I used ask_user to ask something"]),
            .init(type: "assistant.turn_end", timestamp: t3, data: ["turnId": "1"]),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result != nil)
        #expect(result?.type == .question)
    }
    
    @Test("Detect approval alert from exit_plan_mode in message")
    func detectAlertApproval() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:01:01Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.message", timestamp: t2, data: ["content": "Please exit_plan_mode to approve"]),
            .init(type: "assistant.turn_end", timestamp: t3, data: ["turnId": "1"]),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result != nil)
        #expect(result?.type == .approval)
    }
    
    @Test("No alert when user responded after turn end")
    func noAlertAfterUserResponse() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:02:00Z")
        
        let events: [EventParser.Event] = [
            .init(type: "assistant.message", timestamp: t1),
            .init(type: "assistant.turn_end", timestamp: t2, data: ["turnId": "0"]),
            .init(type: "user.message", timestamp: t3),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result == nil)
    }
    
    @Test("No alert when user responded after completion")
    func noAlertAfterCompletionAndResponse() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:05:00Z")
        
        let events: [EventParser.Event] = [
            .init(type: "session.task_complete", timestamp: t1, data: ["summary": "Done"]),
            .init(type: "user.message", timestamp: t2),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result == nil)
    }
    
    @Test("Turn ended cleanly without question is completion")
    func detectGenericWaiting() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:01:01Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.message", timestamp: t2, data: ["content": "Here is the answer"]),
            .init(type: "assistant.turn_end", timestamp: t3, data: ["turnId": "1"]),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result != nil)
        #expect(result?.type == .completion)
    }
    
    @Test("Empty events returns no alert")
    func detectAlertEmptyEvents() {
        let result = EventParser.detectAlert(events: [])
        #expect(result == nil)
    }
    
    @Test("Detect working state when turn started but not ended")
    func detectWorkingState() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:00:01Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.turn_start", timestamp: t2),
        ]
        
        let result = EventParser.detectState(events: events)
        #expect(result != nil)
        #expect(result?.type == .working)
    }
    
    @Test("Detect working state when user message is most recent")
    func detectWorkingFromUserMessage() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:02:00Z")
        
        let events: [EventParser.Event] = [
            .init(type: "assistant.turn_end", timestamp: t1),
            .init(type: "session.task_complete", timestamp: t1),
            .init(type: "user.message", timestamp: t2),
            .init(type: "user.message", timestamp: t3),
        ]
        
        let result = EventParser.detectState(events: events)
        #expect(result?.type == .working)
    }
    
    @Test("Detect question from ask_user tool execution")
    func detectQuestionFromToolExecution() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:01:01Z")
        let t4 = date("2026-06-11T10:01:02Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.message", timestamp: t2, data: ["content": "calling ask_user now"]),
            .init(type: "tool.execution_start", timestamp: t3, data: ["toolName": "ask_user"]),
            .init(type: "assistant.turn_end", timestamp: t4, data: ["turnId": "1"]),
        ]
        
        let result = EventParser.detectState(events: events)
        #expect(result?.type == .question)
    }
    
    @Test("Detect completion from task_complete tool without session.task_complete event")
    func detectCompletionFromToolName() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:01:01Z")
        let t4 = date("2026-06-11T10:01:02Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.message", timestamp: t2, data: ["content": "All done"]),
            .init(type: "tool.execution_start", timestamp: t3, data: ["toolName": "task_complete"]),
            .init(type: "assistant.turn_end", timestamp: t4, data: ["turnId": "1"]),
        ]
        
        let result = EventParser.detectState(events: events)
        #expect(result?.type == .completion)
    }
    
    @Test("detectAlert excludes working state")
    func detectAlertExcludesWorking() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:00:01Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.turn_start", timestamp: t2),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result == nil)
    }
    
    @Test("Plan changed without exit_plan_mode is completion not approval")
    func planChangedWithoutExitPlanMode() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:01:01Z")
        let t4 = date("2026-06-11T10:01:02Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "session.plan_changed", timestamp: t2),
            .init(type: "assistant.message", timestamp: t3, data: ["content": "Investigation complete"]),
            .init(type: "assistant.turn_end", timestamp: t4, data: ["turnId": "1"]),
        ]
        
        let result = EventParser.detectState(events: events)
        #expect(result?.type == .completion)
    }
    
    @Test("Completion takes priority over turn_end")
    func completionPriority() {
        let t1 = date("2026-06-11T10:00:00Z")
        let t2 = date("2026-06-11T10:01:00Z")
        let t3 = date("2026-06-11T10:01:01Z")
        
        let events: [EventParser.Event] = [
            .init(type: "user.message", timestamp: t1),
            .init(type: "assistant.turn_end", timestamp: t2, data: ["turnId": "1"]),
            .init(type: "session.task_complete", timestamp: t3, data: ["summary": "All done"]),
        ]
        
        let result = EventParser.detectAlert(events: events)
        #expect(result?.type == .completion)
    }
    
    // MARK: - Helpers
    
    private func date(_ iso: String) -> Date {
        EventParser.parseDate(iso)!
    }
}
