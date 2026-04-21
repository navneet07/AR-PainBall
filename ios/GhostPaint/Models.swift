// GhostPaint · Codable message types shared with the Node server
// Keep in exact sync with server/game.mjs message shapes.

import Foundation
import SwiftUI

// ─── phase ──────────────────────────────────────────────────
enum ClientPhase {
    case disconnected
    case connecting
    case joining          // connected, awaiting "joined" response
    case inLobby          // in lobby, server phase is "lobby"
    case countdown        // server phase is "countdown"
    case playing
    case ended
}

// ─── incoming messages (server → client) ───────────────────
enum ServerMessage: Decodable {
    case joined(Player)
    case state(PublicState)
    case gameStart
    case hit(shooterId: String, victimId: String, damage: Int, hp: Int)
    case damage(shooterId: String, amount: Int, hp: Int)
    case kill(shooterId: String, victimId: String)
    case respawn(playerId: String)
    case gameEnd(winnerId: String?, reason: String)
    case reloadComplete(ammo: Int)
    case shotMissed(shooterId: String)
    case dryFire
    case error(String)
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case type, you, state, shooterId, victimId, damage, hp, amount
        case playerId, winnerId, reason, ammo, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "joined":
            self = .joined(try c.decode(Player.self, forKey: .you))
        case "state":
            self = .state(try c.decode(PublicState.self, forKey: .state))
        case "game_start":
            self = .gameStart
        case "hit":
            self = .hit(
                shooterId: try c.decode(String.self, forKey: .shooterId),
                victimId:  try c.decode(String.self, forKey: .victimId),
                damage:    try c.decode(Int.self,    forKey: .damage),
                hp:        try c.decode(Int.self,    forKey: .hp)
            )
        case "damage":
            self = .damage(
                shooterId: try c.decode(String.self, forKey: .shooterId),
                amount:    try c.decode(Int.self,    forKey: .amount),
                hp:        try c.decode(Int.self,    forKey: .hp)
            )
        case "kill":
            self = .kill(
                shooterId: try c.decode(String.self, forKey: .shooterId),
                victimId:  try c.decode(String.self, forKey: .victimId)
            )
        case "respawn":
            self = .respawn(playerId: try c.decode(String.self, forKey: .playerId))
        case "game_end":
            self = .gameEnd(
                winnerId: try c.decodeIfPresent(String.self, forKey: .winnerId),
                reason:   try c.decodeIfPresent(String.self, forKey: .reason) ?? "time_up"
            )
        case "reload_complete":
            self = .reloadComplete(ammo: try c.decode(Int.self, forKey: .ammo))
        case "shot_missed":
            self = .shotMissed(shooterId: try c.decode(String.self, forKey: .shooterId))
        case "dry_fire":
            self = .dryFire
        case "error":
            self = .error(try c.decode(String.self, forKey: .error))
        default:
            self = .unknown(type)
        }
    }
}

// ─── outgoing messages (client → server) ───────────────────
enum ClientMessage: Encodable {
    case join(name: String)
    case ready(Bool)
    case fire(targetBib: String?, worldPos: [Double]?)
    case position(lat: Double, lng: Double, heading: Double)
    case forceStart
    case resetLobby
    case leave

    enum CodingKeys: String, CodingKey {
        case type, name, ready, targetBib, worldPos, lat, lng, heading
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .join(let name):
            try c.encode("join", forKey: .type)
            try c.encode(name, forKey: .name)
        case .ready(let r):
            try c.encode("ready", forKey: .type)
            try c.encode(r, forKey: .ready)
        case .fire(let bib, let pos):
            try c.encode("fire", forKey: .type)
            try c.encodeIfPresent(bib, forKey: .targetBib)
            try c.encodeIfPresent(pos, forKey: .worldPos)
        case .position(let lat, let lng, let h):
            try c.encode("position", forKey: .type)
            try c.encode(lat, forKey: .lat)
            try c.encode(lng, forKey: .lng)
            try c.encode(h, forKey: .heading)
        case .forceStart:
            try c.encode("force_start", forKey: .type)
        case .resetLobby:
            try c.encode("reset_lobby", forKey: .type)
        case .leave:
            try c.encode("leave", forKey: .type)
        }
    }
}

// ─── data models mirrored from game.mjs ─────────────────────
struct Player: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let bibId: String
    let bibName: String
    let color: String       // "#RRGGBB"
    let hp: Int
    let ammo: Int
    let reloading: Bool
    let kills: Int
    let deaths: Int
    let hits: Int
    let shots: Int
    let ready: Bool
    let alive: Bool
}

struct PublicState: Codable {
    let phase: String            // lobby|countdown|playing|ended
    let countdownEndsAt: Double?
    let matchStartedAt: Double?
    let matchEndsAt: Double?
    let winner: String?
    let players: [Player]
    let killFeed: [KillEntry]?
}

struct KillEntry: Codable, Identifiable {
    var id: String { "\(shooterId)-\(victimId)-\(at)" }
    let shooterId: String
    let victimId: String
    let at: Double
}

// ─── colour helper (SwiftUI) ────────────────────────────────
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self = Color(
            red:   Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8)  & 0xff) / 255,
            blue:  Double(rgb         & 0xff) / 255
        )
    }
}
