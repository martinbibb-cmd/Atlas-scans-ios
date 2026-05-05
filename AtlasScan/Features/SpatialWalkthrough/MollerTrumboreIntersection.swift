import Foundation
import simd

// MARK: - MollerTrumboreIntersection
//
// Pure Swift implementation of the Möller–Trumbore ray-triangle intersection
// algorithm for computing LiDAR clearance distances without physical markers.
//
// Coordinate convention: ARKit right-handed Y-up (metric metres).
//   Horizontal plane: X, Z
//   Vertical:         Y
//
// Usage:
//   let result = MollerTrumboreIntersection.intersect(
//       rayOrigin: origin, rayDirection: direction,
//       v0: p0, v1: p1, v2: p2
//   )
//
// Reference: "Fast, Minimum Storage Ray/Triangle Intersection",
// Möller & Trumbore, 1997. doi:10.1145/1198555.1198746.

enum MollerTrumboreIntersection {

    // MARK: - Constants

    /// Small epsilon used to avoid false positives at triangle edges.
    static let epsilon: Float = 1e-6

    // MARK: - Single triangle intersection

    /// Tests whether a ray intersects a triangle and returns the hit distance.
    ///
    /// - Parameters:
    ///   - rayOrigin:    World-space origin of the ray (ARKit Y-up metres).
    ///   - rayDirection: Normalised world-space direction of the ray.
    ///   - v0, v1, v2:  Triangle vertices in ARKit Y-up metres.
    /// - Returns: Distance along `rayDirection` to the intersection point, or
    ///            `nil` when the ray misses, is parallel, or hits the back face.
    static func intersect(
        rayOrigin: SIMD3<Float>,
        rayDirection: SIMD3<Float>,
        v0: SIMD3<Float>,
        v1: SIMD3<Float>,
        v2: SIMD3<Float>
    ) -> Float? {

        let edge1 = v1 - v0
        let edge2 = v2 - v0

        let h = cross(rayDirection, edge2)
        let det = dot(edge1, h)

        // Ray is parallel to the triangle — no intersection.
        guard abs(det) > epsilon else { return nil }

        let invDet: Float = 1.0 / det
        let s = rayOrigin - v0
        let u = invDet * dot(s, h)
        guard u >= 0, u <= 1 else { return nil }

        let q = cross(s, edge1)
        let v = invDet * dot(rayDirection, q)
        guard v >= 0, (u + v) <= 1 else { return nil }

        let t = invDet * dot(edge2, q)
        guard t > epsilon else { return nil }   // intersection behind ray origin

        return t
    }

    // MARK: - Mesh intersection

    /// Finds the nearest intersection distance from `rayOrigin` along
    /// `rayDirection` against a flat triangle mesh described by interleaved
    /// vertex and index arrays.
    ///
    /// Suitable for use against `ARMeshAnchor`-derived geometry after extracting
    /// vertices and face indices into contiguous Float32 and UInt32 arrays.
    ///
    /// - Parameters:
    ///   - rayOrigin:    World-space ray origin (Y-up metres).
    ///   - rayDirection: Normalised world-space ray direction.
    ///   - vertices:     Flat array of (x,y,z) Float32 vertex components.
    ///   - indices:      Flat array of UInt32 triangle indices (3 per triangle).
    /// - Returns: Distance to the nearest hit, or `nil` when nothing intersects.
    static func nearestHit(
        rayOrigin: SIMD3<Float>,
        rayDirection: SIMD3<Float>,
        vertices: [Float],
        indices: [UInt32]
    ) -> Float? {

        guard vertices.count >= 3, indices.count >= 3 else { return nil }

        var nearest: Float? = nil

        let triangleCount = indices.count / 3
        for i in 0 ..< triangleCount {
            let base = i * 3
            let i0 = Int(indices[base])
            let i1 = Int(indices[base + 1])
            let i2 = Int(indices[base + 2])

            guard i0 * 3 + 2 < vertices.count,
                  i1 * 3 + 2 < vertices.count,
                  i2 * 3 + 2 < vertices.count
            else { continue }

            let v0 = SIMD3<Float>(vertices[i0 * 3], vertices[i0 * 3 + 1], vertices[i0 * 3 + 2])
            let v1 = SIMD3<Float>(vertices[i1 * 3], vertices[i1 * 3 + 1], vertices[i1 * 3 + 2])
            let v2 = SIMD3<Float>(vertices[i2 * 3], vertices[i2 * 3 + 1], vertices[i2 * 3 + 2])

            if let t = intersect(rayOrigin: rayOrigin, rayDirection: rayDirection, v0: v0, v1: v1, v2: v2) {
                if nearest == nil || t < nearest! {
                    nearest = t
                }
            }
        }
        return nearest
    }

    // MARK: - Clearance axis helper

    /// Convenience: casts a ray from `origin` in each of the five clearance
    /// directions (front, rear, left, right, ceiling) against a mesh and returns
    /// the measured distances.
    ///
    /// "Front" is the –Z direction (into the room from the appliance face), which
    /// matches the ARKit right-handed Y-up convention where the engineer faces –Z.
    ///
    /// - Parameters:
    ///   - origin:    3-D position of the appliance anchor (Y-up metres).
    ///   - vertices:  Flat Float32 vertex array from the LiDAR mesh.
    ///   - indices:   Flat UInt32 index array from the LiDAR mesh.
    /// - Returns: Dictionary mapping `LiDARMeasurementAxis` → optional distance.
    static func clearanceDistances(
        from origin: SIMD3<Float>,
        vertices: [Float],
        indices: [UInt32]
    ) -> [LiDARMeasurementAxis: Float?] {

        let axes: [(LiDARMeasurementAxis, SIMD3<Float>)] = [
            (.front,   SIMD3<Float>( 0,  0, -1)),
            (.rear,    SIMD3<Float>( 0,  0,  1)),
            (.left,    SIMD3<Float>(-1,  0,  0)),
            (.right,   SIMD3<Float>( 1,  0,  0)),
            (.ceiling, SIMD3<Float>( 0,  1,  0)),
        ]

        var result: [LiDARMeasurementAxis: Float?] = [:]
        for (axis, direction) in axes {
            result[axis] = nearestHit(
                rayOrigin: origin,
                rayDirection: normalize(direction),
                vertices: vertices,
                indices: indices
            )
        }
        return result
    }
}
