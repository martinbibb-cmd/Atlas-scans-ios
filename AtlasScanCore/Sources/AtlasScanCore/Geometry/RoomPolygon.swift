/// RoomPolygon — Polygon geometry utilities for room capture.
///
/// Provides area calculation via the shoelace (Gauss) formula
/// and centroid computation for V2 room polygons.

import Foundation

// MARK: - RoomPolygon

public struct RoomPolygon: Sendable {
    public let vertices: [Vertex2D]

    public init(vertices: [Vertex2D]) {
        self.vertices = vertices
    }

    /// Signed area using the shoelace formula (m²).
    /// Positive for counter-clockwise winding, negative for clockwise.
    public var signedArea: Double {
        let n = vertices.count
        guard n >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<n {
            let j = (i + 1) % n
            sum += vertices[i].x * vertices[j].z
            sum -= vertices[j].x * vertices[i].z
        }
        return sum / 2.0
    }

    /// Absolute area of the polygon in m².
    public var area: Double { abs(signedArea) }

    /// Centroid in the (X, Z) plane.
    public var centroid: Vertex2D {
        let n = vertices.count
        guard n >= 3 else {
            let avgX = vertices.reduce(0.0) { $0 + $1.x } / Double(max(n, 1))
            let avgZ = vertices.reduce(0.0) { $0 + $1.z } / Double(max(n, 1))
            return Vertex2D(x: avgX, z: avgZ)
        }
        let a = signedArea
        guard abs(a) > 1e-10 else {
            let avgX = vertices.reduce(0.0) { $0 + $1.x } / Double(n)
            let avgZ = vertices.reduce(0.0) { $0 + $1.z } / Double(n)
            return Vertex2D(x: avgX, z: avgZ)
        }
        var cx = 0.0, cz = 0.0
        for i in 0..<n {
            let j = (i + 1) % n
            let cross = vertices[i].x * vertices[j].z - vertices[j].x * vertices[i].z
            cx += (vertices[i].x + vertices[j].x) * cross
            cz += (vertices[i].z + vertices[j].z) * cross
        }
        let factor = 1.0 / (6.0 * a)
        return Vertex2D(x: cx * factor, z: cz * factor)
    }

    /// Returns `true` when the polygon is wound counter-clockwise.
    public var isCounterClockwise: Bool { signedArea > 0 }

    /// Returns a copy with counter-clockwise winding enforced.
    public var normalised: RoomPolygon {
        isCounterClockwise ? self : RoomPolygon(vertices: vertices.reversed())
    }

    /// Perimeter length in metres.
    public var perimeter: Double {
        let n = vertices.count
        guard n >= 2 else { return 0 }
        var total = 0.0
        for i in 0..<n {
            let j = (i + 1) % n
            let dx = vertices[j].x - vertices[i].x
            let dz = vertices[j].z - vertices[i].z
            total += (dx*dx + dz*dz).squareRoot()
        }
        return total
    }
}
