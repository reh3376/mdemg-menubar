import Foundation

struct RSICStatus: Codable {
    let overallHealth: Double
    let retrievalQuality: Double
    let memoryHealth: Double
    let edgeHealth: Double
    let learningPhase: String
    let orphanRatio: Double
}
