import Foundation
import os.signpost

enum XTPerformanceTrace {
    struct Span {
        fileprivate let name: StaticString
        fileprivate let id: OSSignpostID
    }

    private static let log = OSLog(
        subsystem: "com.xterminal.xt",
        category: "performance"
    )

    static func begin(_ name: StaticString, _ detail: String = "") -> Span {
        let id = OSSignpostID(log: log)
        if detail.isEmpty {
            os_signpost(.begin, log: log, name: name, signpostID: id)
        } else {
            os_signpost(
                .begin,
                log: log,
                name: name,
                signpostID: id,
                "%{public}@",
                detail as NSString
            )
        }
        return Span(name: name, id: id)
    }

    static func end(_ span: Span, _ detail: String = "") {
        if detail.isEmpty {
            os_signpost(.end, log: log, name: span.name, signpostID: span.id)
        } else {
            os_signpost(
                .end,
                log: log,
                name: span.name,
                signpostID: span.id,
                "%{public}@",
                detail as NSString
            )
        }
    }

    static func event(_ name: StaticString, _ detail: String = "") {
        if detail.isEmpty {
            os_signpost(.event, log: log, name: name)
        } else {
            os_signpost(
                .event,
                log: log,
                name: name,
                "%{public}@",
                detail as NSString
            )
        }
    }
}
