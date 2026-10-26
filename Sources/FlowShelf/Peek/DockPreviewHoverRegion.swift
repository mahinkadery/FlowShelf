import Foundation

enum DockPreviewHoverRegion {
    static func contains(_ point: CGPoint, icon: CGRect, panel: CGRect, edge: DockPosition) -> Bool {
        guard !icon.isEmpty, !panel.isEmpty else { return false }
        if icon.contains(point) || panel.insetBy(dx: -2, dy: -2).contains(point) { return true }
        switch edge {
        case .bottom, .unknown:
            return corridor(along: point.y, across: point.x,
                            start: icon.midY, end: panel.minY + 4,
                            source: icon.minX...icon.maxX, destination: panel.minX...panel.maxX)
        case .top:
            return corridor(along: -point.y, across: point.x,
                            start: -icon.midY, end: -panel.maxY + 4,
                            source: icon.minX...icon.maxX, destination: panel.minX...panel.maxX)
        case .left:
            return corridor(along: point.x, across: point.y,
                            start: icon.midX, end: panel.minX + 4,
                            source: icon.minY...icon.maxY, destination: panel.minY...panel.maxY)
        case .right:
            return corridor(along: -point.x, across: point.y,
                            start: -icon.midX, end: -panel.maxX + 4,
                            source: icon.minY...icon.maxY, destination: panel.minY...panel.maxY)
        }
    }

    private static func corridor(along: CGFloat, across: CGFloat, start: CGFloat, end: CGFloat,
                                 source: ClosedRange<CGFloat>, destination: ClosedRange<CGFloat>) -> Bool {
        guard end > start, along >= start, along <= end else { return false }
        let progress = (along - start) / (end - start)
        let lower = source.lowerBound + (destination.lowerBound - source.lowerBound) * progress - 6
        let upper = source.upperBound + (destination.upperBound - source.upperBound) * progress + 6
        return across >= lower && across <= upper
    }
}
