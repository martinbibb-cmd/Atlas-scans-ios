import Foundation

enum V2IdentifiableDedupe {
    static func byUUID<T: Identifiable>(primary: [T], secondary: [T]) -> [T] where T.ID == UUID {
        var seen: Set<UUID> = []
        var deduped: [T] = []
        deduped.reserveCapacity(primary.count + secondary.count)
        for item in primary where seen.insert(item.id).inserted {
            deduped.append(item)
        }
        for item in secondary where seen.insert(item.id).inserted {
            deduped.append(item)
        }
        return deduped
    }
}
