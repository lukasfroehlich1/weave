import Foundation

@Observable
class TerminalTab: Identifiable {
    let id = UUID()
    var title: String = "Terminal"
    var surfaceView: GhosttySurfaceView?
    var agentStatus: AgentStatus = .idle
}
