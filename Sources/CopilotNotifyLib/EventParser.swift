import Foundation

/// Parses events.jsonl files to detect session state.
public struct EventParser {
    
    /// Represents a parsed event from events.jsonl
    public struct Event {
        public let type: String
        public let timestamp: Date?
        public let data: [String: Any]
        
        public init(type: String, timestamp: Date?, data: [String: Any] = [:]) {
            self.type = type
            self.timestamp = timestamp
            self.data = data
        }
    }
    
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    public static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string) ?? fallbackDateFormatter.date(from: string)
    }
    
    /// Reads events from a jsonl file, optionally starting after a byte offset.
    /// Returns the events and the new byte offset.
    public static func readEvents(from path: String, afterOffset: UInt64 = 0) -> (events: [Event], newOffset: UInt64) {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return ([], 0)
        }
        defer { fileHandle.closeFile() }
        
        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > afterOffset else {
            return ([], afterOffset)
        }
        
        fileHandle.seek(toFileOffset: afterOffset)
        guard let data = try? fileHandle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return ([], afterOffset)
        }
        
        var events: [Event] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            
            let timestamp: Date?
            if let ts = json["timestamp"] as? String {
                timestamp = parseDate(ts)
            } else {
                timestamp = nil
            }
            
            let eventData = json["data"] as? [String: Any] ?? [:]
            events.append(Event(type: type, timestamp: timestamp, data: eventData))
        }
        
        return (events, fileSize)
    }
    
    /// Determines the current state of a session based on its events.
    /// Returns the alert type + timestamp. Returns `.working` if the agent is actively processing.
    /// Returns nil only if there are no meaningful events at all.
    public static func detectState(events: [Event]) -> (type: AlertType, since: Date)? {
        // Walk events in reverse to find the latest meaningful state
        var lastTurnEnd: Event?
        var lastUserMessage: Event?
        var lastTaskComplete: Event?
        var lastTurnStart: Event?
        // Collect assistant messages and tool calls from the most recent turn only
        var recentTurnMessages: [Event] = []
        var recentTurnTools: [Event] = []
        var foundTurnEnd = false
        
        for event in events.reversed() {
            switch event.type {
            case "session.task_complete" where lastTaskComplete == nil:
                lastTaskComplete = event
            case "assistant.turn_end" where lastTurnEnd == nil:
                lastTurnEnd = event
                foundTurnEnd = true
            case "assistant.turn_start" where lastTurnStart == nil:
                lastTurnStart = event
            case "user.message" where lastUserMessage == nil:
                lastUserMessage = event
            case "assistant.message" where foundTurnEnd && lastTurnStart == nil:
                recentTurnMessages.append(event)
            case "tool.execution_start" where foundTurnEnd && lastTurnStart == nil:
                recentTurnTools.append(event)
            case "tool.execution_complete" where foundTurnEnd && lastTurnStart == nil:
                recentTurnTools.append(event)
            default:
                break
            }
            if lastTurnEnd != nil && lastUserMessage != nil && lastTaskComplete != nil
                && lastTurnStart != nil {
                break
            }
        }
        
        let userTime = lastUserMessage?.timestamp ?? Date.distantPast
        
        // If a turn started AFTER the last turn ended, agent is currently working
        if let turnStart = lastTurnStart, let turnEnd = lastTurnEnd {
            let startTime = turnStart.timestamp ?? Date()
            let endTime = turnEnd.timestamp ?? Date.distantPast
            if startTime > endTime {
                return (.working, startTime)
            }
        }
        
        // If task_complete is the most recent significant event (after last user message)
        if let tc = lastTaskComplete {
            let tcTime = tc.timestamp ?? Date()
            if tcTime > userTime {
                return (.completion, tcTime)
            }
        }
        
        // If turn ended and no user message came after → session is waiting
        if let turnEnd = lastTurnEnd {
            let turnEndTime = turnEnd.timestamp ?? Date()
            
            if turnEndTime > userTime {
                // Check assistant messages from this most recent turn for ask_user/approval indicators
                let hasQuestion = recentTurnMessages.contains { event in
                    let content = event.data["content"] as? String ?? ""
                    return content.contains("ask_user") || content.contains("elicitation")
                }
                if hasQuestion {
                    return (.question, turnEndTime)
                }
                
                // Check tool calls for task_complete tool (marks completion even without session.task_complete event)
                let hasTaskCompleteTool = recentTurnTools.contains { event in
                    let name = event.data["toolName"] as? String ?? event.data["name"] as? String ?? ""
                    return name == "task_complete"
                }
                if hasTaskCompleteTool {
                    return (.completion, turnEndTime)
                }
                
                // Check if last message contains approval-related content
                let hasApproval = recentTurnMessages.contains { event in
                    let content = event.data["content"] as? String ?? ""
                    return content.contains("exit_plan_mode")
                }
                if hasApproval {
                    return (.approval, turnEndTime)
                }
                
                // Turn ended cleanly with no question/approval → session is complete/idle
                return (.completion, turnEndTime)
            }
        }
        
        // If turn started but hasn't ended yet → agent is working
        if let turnStart = lastTurnStart {
            let startTime = turnStart.timestamp ?? Date()
            if startTime > userTime {
                return (.working, startTime)
            }
        }
        
        // User message is most recent → agent is working (processing the message)
        if lastUserMessage != nil {
            return (.working, userTime)
        }
        
        return nil
    }
    
    /// Legacy wrapper — returns nil for "working" state (only returns attention-needed states).
    public static func detectAlert(events: [Event]) -> (type: AlertType, since: Date)? {
        guard let state = detectState(events: events) else { return nil }
        if state.type == .working { return nil }
        return state
    }
}
