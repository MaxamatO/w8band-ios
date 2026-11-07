import UIKit

/// Empty chart surface. Its layout and background are editable in Main.storyboard.
@IBDesignable
final class TrajectoryView: UIView {
    var points: [TrajectoryPoint] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    
    private func drawTrajectory(in plot: CGRect) {
        guard !points.isEmpty else { return }

        let positions = points.map {
            CGPoint(
                x: CGFloat($0.horizontalMm),
                y: CGFloat($0.verticalMm)
            )
        }

        let minX = min(0, positions.map(\.x).min()!)
        let maxX = max(0, positions.map(\.x).max()!)
        let minZ = min(0, positions.map(\.y).min()!)
        let maxZ = max(0, positions.map(\.y).max()!)

        let spanX = max(maxX - minX, 1)
        let spanZ = max(maxZ - minZ, 1)

        let scale = min(
            plot.width / spanX,
            plot.height / spanZ
        )

        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2

        func screenPoint(_ position: CGPoint) -> CGPoint {
            CGPoint(
                x: plot.midX + (position.x - centerX) * scale,
                y: plot.midY - (position.y - centerZ) * scale
            )
        }

        let path = UIBezierPath()
        path.move(to: screenPoint(positions[0]))

        for position in positions.dropFirst() {
            path.addLine(to: screenPoint(position))
        }

        UIColor.systemGreen.setStroke()
        path.lineWidth = 2
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()

        let origin = screenPoint(.zero)

        UIColor.systemOrange.setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: origin.x - 4,
                y: origin.y - 4,
                width: 8,
                height: 8
            )
        ).fill()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let plot = bounds.insetBy(dx: 24, dy: 24)
        guard plot.width > 0, plot.height > 0 else { return }

        context.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(0.5)
        for index in 0...4 {
            let fraction = CGFloat(index) / 4
            let x = plot.minX + fraction * plot.width
            let y = plot.minY + fraction * plot.height
            context.move(to: CGPoint(x: x, y: plot.minY))
            context.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        context.strokePath()

        let style: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.white.withAlphaComponent(0.6)
        ]
        ("X" as NSString).draw(at: CGPoint(x: plot.maxX - 6, y: plot.maxY + 6), withAttributes: style)
        ("Z" as NSString).draw(at: CGPoint(x: plot.minX - 14, y: plot.minY - 6), withAttributes: style)

        drawTrajectory(in: plot)
    }
}
