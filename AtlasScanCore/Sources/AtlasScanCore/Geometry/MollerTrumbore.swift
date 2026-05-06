/// MollerTrumbore — Ray–triangle intersection and AABB clearance conflict detection.
///
/// Implements the Möller–Trumbore algorithm for fast ray–triangle intersection
/// tests used to detect when a RoomPlan mesh triangle overlaps the ghost-box
/// clearance volume of a pinned appliance.

import Foundation

// MARK: - Vec3

public struct Vec3: Sendable {
    public var x, y, z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x; self.y = y; self.z = z
    }

    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(lhs.x+rhs.x, lhs.y+rhs.y, lhs.z+rhs.z) }
    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(lhs.x-rhs.x, lhs.y-rhs.y, lhs.z-rhs.z) }
    public static func * (lhs: Vec3, rhs: Double) -> Vec3 { Vec3(lhs.x*rhs, lhs.y*rhs, lhs.z*rhs) }
    public static func * (lhs: Double, rhs: Vec3) -> Vec3 { rhs * lhs }

    public func dot(_ other: Vec3) -> Double { x*other.x + y*other.y + z*other.z }

    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    public var magnitudeSquared: Double { x*x + y*y + z*z }
    public var magnitude: Double { magnitudeSquared.squareRoot() }

    public var normalized: Vec3 {
        let m = magnitude
        guard m > 1e-10 else { return Vec3(0, 1, 0) }
        return self * (1.0 / m)
    }
}

// MARK: - Möller–Trumbore

public enum MollerTrumbore {

    private static let epsilon = 1e-7

    /// Returns the parametric `t` (ray distance) of the intersection, or `nil`
    /// if the ray does not intersect the triangle or is parallel.
    ///
    /// - Parameters:
    ///   - origin:    Ray origin.
    ///   - direction: Ray direction (need not be normalised).
    ///   - v0, v1, v2: Triangle vertices.
    public static func intersect(
        origin: Vec3,
        direction: Vec3,
        v0: Vec3, v1: Vec3, v2: Vec3
    ) -> Double? {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = direction.cross(edge2)
        let a = edge1.dot(h)

        guard abs(a) > epsilon else { return nil }  // parallel

        let f = 1.0 / a
        let s = origin - v0
        let u = f * s.dot(h)
        guard (0.0...1.0).contains(u) else { return nil }

        let q = s.cross(edge1)
        let v = f * direction.dot(q)
        guard v >= 0.0 && (u + v) <= 1.0 else { return nil }

        let t = f * edge2.dot(q)
        guard t > epsilon else { return nil }
        return t
    }

    /// Returns `true` when any point of the triangle lies inside or intersects
    /// the axis-aligned bounding box defined by `min` and `max`.
    public static func intersectsAABB(
        v0: Vec3, v1: Vec3, v2: Vec3,
        aabbMin: Vec3, aabbMax: Vec3
    ) -> Bool {
        // Quick vertex containment test.
        for v in [v0, v1, v2] {
            if v.x >= aabbMin.x && v.x <= aabbMax.x &&
               v.y >= aabbMin.y && v.y <= aabbMax.y &&
               v.z >= aabbMin.z && v.z <= aabbMax.z {
                return true
            }
        }
        // SAT-based edge/face separating-axis test (9 cross-product axes + 3 face normals + 1 triangle normal).
        return !separatedByAnyAxis(v0: v0, v1: v1, v2: v2, aabbMin: aabbMin, aabbMax: aabbMax)
    }

    // MARK: - SAT helpers

    private static func separatedByAnyAxis(
        v0: Vec3, v1: Vec3, v2: Vec3,
        aabbMin: Vec3, aabbMax: Vec3
    ) -> Bool {
        let center = Vec3(
            (aabbMin.x + aabbMax.x) * 0.5,
            (aabbMin.y + aabbMax.y) * 0.5,
            (aabbMin.z + aabbMax.z) * 0.5
        )
        let half = Vec3(
            (aabbMax.x - aabbMin.x) * 0.5,
            (aabbMax.y - aabbMin.y) * 0.5,
            (aabbMax.z - aabbMin.z) * 0.5
        )
        let p0 = v0 - center
        let p1 = v1 - center
        let p2 = v2 - center

        // AABB face normals
        for axis in [Vec3(1,0,0), Vec3(0,1,0), Vec3(0,0,1)] {
            let r = half.x * abs(axis.x) + half.y * abs(axis.y) + half.z * abs(axis.z)
            let mn = min(p0.dot(axis), p1.dot(axis), p2.dot(axis))
            let mx = max(p0.dot(axis), p1.dot(axis), p2.dot(axis))
            if mn > r || mx < -r { return true }
        }

        // Triangle normal
        let tn = (v1 - v0).cross(v2 - v0)
        let r = half.x * abs(tn.x) + half.y * abs(tn.y) + half.z * abs(tn.z)
        let d = tn.dot(p0)
        if d > r || d < -r { return true }

        // 9 cross-product axes
        let edges = [v1 - v0, v2 - v1, v0 - v2]
        let boxAxes = [Vec3(1,0,0), Vec3(0,1,0), Vec3(0,0,1)]
        for e in edges {
            for a in boxAxes {
                let axis = e.cross(a)
                guard axis.magnitudeSquared > 1e-14 else { continue }
                let r2 = half.x * abs(axis.x) + half.y * abs(axis.y) + half.z * abs(axis.z)
                let mn = min(p0.dot(axis), p1.dot(axis), p2.dot(axis))
                let mx = max(p0.dot(axis), p1.dot(axis), p2.dot(axis))
                if mn > r2 || mx < -r2 { return true }
            }
        }
        return false
    }
}

// MARK: - ClearanceConflictDetector

public enum ClearanceConflictDetector {

    /// Axis-aligned ghost box in world space.
    public struct GhostBox: Sendable {
        public let min: Vec3
        public let max: Vec3

        public init(
            centre: Vec3,
            halfWidth: Double,
            halfHeight: Double,
            halfDepth: Double
        ) {
            self.min = Vec3(centre.x - halfWidth, centre.y - halfHeight, centre.z - halfDepth)
            self.max = Vec3(centre.x + halfWidth, centre.y + halfHeight, centre.z + halfDepth)
        }
    }

    /// Returns `true` when the triangle overlaps the AABB.
    public static func triangleOverlapsAABB(
        v0: Vec3, v1: Vec3, v2: Vec3,
        box: GhostBox
    ) -> Bool {
        MollerTrumbore.intersectsAABB(v0: v0, v1: v1, v2: v2, aabbMin: box.min, aabbMax: box.max)
    }

    /// Tests a flat vertex list (strided by 3 — x,y,z per vertex) and index list
    /// against the ghost box.  Returns the indices of every conflicting triangle.
    public static func meshConflicts(
        vertices: [Float],
        indices: [UInt32],
        box: GhostBox
    ) -> [Int] {
        var conflicting: [Int] = []
        let triCount = indices.count / 3
        for tri in 0..<triCount {
            let i0 = Int(indices[tri * 3])
            let i1 = Int(indices[tri * 3 + 1])
            let i2 = Int(indices[tri * 3 + 2])
            let v0 = Vec3(Double(vertices[i0*3]), Double(vertices[i0*3+1]), Double(vertices[i0*3+2]))
            let v1 = Vec3(Double(vertices[i1*3]), Double(vertices[i1*3+1]), Double(vertices[i1*3+2]))
            let v2 = Vec3(Double(vertices[i2*3]), Double(vertices[i2*3+1]), Double(vertices[i2*3+2]))
            if triangleOverlapsAABB(v0: v0, v1: v1, v2: v2, box: box) {
                conflicting.append(tri)
            }
        }
        return conflicting
    }

    /// Derives a `QAFlagV1` from a set of conflicting triangle indices.
    public static func qaFlag(
        roomId: UUID,
        conflictingTriangles: [Int]
    ) -> QAFlagV1 {
        if conflictingTriangles.isEmpty {
            return QAFlagV1(type: .clearancePass, roomId: roomId, detail: "No clearance conflicts detected.")
        } else {
            return QAFlagV1(
                type: .clearanceConflict,
                roomId: roomId,
                detail: "\(conflictingTriangles.count) triangle(s) intrude into the clearance envelope."
            )
        }
    }
}
