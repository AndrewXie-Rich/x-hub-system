import Foundation

enum AXMemoryPipelineNotifications {
    static let coarseStart = Notification.Name("xterminal.memory.coarse.start")
    static let coarseEnd = Notification.Name("xterminal.memory.coarse.end")
    static let refineStart = Notification.Name("xterminal.memory.refine.start")
    static let refineEnd = Notification.Name("xterminal.memory.refine.end")
}
