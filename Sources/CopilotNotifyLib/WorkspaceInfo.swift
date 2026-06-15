import Foundation

/// Reads workspace.yaml for session metadata.
public struct WorkspaceInfo {
    public let id: String
    public let summary: String
    public let cwd: String?
    public let updatedAt: Date?
    
    /// Parses a workspace.yaml file (simple key: value format).
    public static func parse(from path: String) -> WorkspaceInfo? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        
        var dict: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            dict[key] = value
        }
        
        guard let id = dict["id"], !id.isEmpty else { return nil }
        
        let summary = dict["name"] ?? dict["summary"] ?? "Untitled Session"
        let cwd = dict["cwd"]
        let updatedAt: Date?
        if let ts = dict["updated_at"] {
            updatedAt = EventParser.parseDate(ts)
        } else {
            updatedAt = nil
        }
        
        return WorkspaceInfo(id: id, summary: summary, cwd: cwd, updatedAt: updatedAt)
    }
}
