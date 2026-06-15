import SwiftUI

/// SwiftUI view for the session alert list shown in the popover.
public struct SessionListView: View {
    public let alerts: [SessionAlert]
    public let onSelect: (SessionAlert) -> Void
    public let onDismiss: (SessionAlert) -> Void
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if alerts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("All clear!")
                        .font(.headline)
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding()
            } else {
                Text("Active Sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(alerts.sorted(by: { sortOrder($0) < sortOrder($1) })) { alert in
                            AlertRow(alert: alert, onSelect: onSelect, onDismiss: onDismiss)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .frame(width: 340)
    }
    
    /// Sort: needs-attention items first (by recency), then working items.
    private func sortOrder(_ alert: SessionAlert) -> Int {
        switch alert.alertType {
        case .question, .approval, .completion: return 0
        case .working: return 1
        }
    }
}

struct AlertRow: View {
    let alert: SessionAlert
    public let onSelect: (SessionAlert) -> Void
    public let onDismiss: (SessionAlert) -> Void
    
    public var body: some View {
        Button(action: { onSelect(alert) }) {
            HStack(spacing: 10) {
                // Alert type icon
                alertIcon
                    .font(.system(size: 18))
                    .frame(width: 28)
                
                // Session info
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.summary)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(alertTypeLabel)
                            .font(.caption.weight(.medium))
                            .foregroundColor(alertColor)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(timeAgo(since: alert.since))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Dismiss button
                Button(action: {
                    onDismiss(alert)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.03))
    }
    
    private var alertIcon: some View {
        Group {
            switch alert.alertType {
            case .completion:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(alertColor)
            case .question:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(alertColor)
            case .approval:
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(alertColor)
            case .working:
                Image(systemName: "gear")
                    .foregroundColor(alertColor)
            }
        }
    }
    
    private var alertTypeLabel: String {
        switch alert.alertType {
        case .completion: return "Completed"
        case .question: return "Question"
        case .approval: return "Needs approval"
        case .working: return "Working"
        }
    }
    
    private var alertColor: Color {
        switch alert.alertType {
        case .completion: return Color(red: 0.2, green: 0.55, blue: 0.2)
        case .question: return Color(red: 0.7, green: 0.4, blue: 0.0)
        case .approval: return Color(red: 0.2, green: 0.35, blue: 0.7)
        case .working: return Color(red: 0.4, green: 0.4, blue: 0.45)
        }
    }
    
    private func timeAgo(since: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(since))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
