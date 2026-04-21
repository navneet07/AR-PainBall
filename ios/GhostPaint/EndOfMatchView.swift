// GhostPaint · end-of-match scoreboard

import SwiftUI

struct EndOfMatchView: View {
    @EnvironmentObject var client: GameClient

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#15102a"), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            VStack(spacing: 24) {
                banner
                if let s = client.state {
                    scoreboard(players: s.players, winnerId: s.winner)
                }
                Button(action: { client.leave() }) {
                    Text("LEAVE").tracking(6).padding(.vertical, 12).frame(maxWidth: 220)
                }
                .buttonStyle(IronManButton(color: Color(hex: "#ff3040")))
            }
            .padding()
        }
    }

    var banner: some View {
        let winnerP = client.state?.players.first { $0.id == client.state?.winner }
        let iWon = winnerP?.id == client.me?.id
        return VStack(spacing: 8) {
            Text(iWon ? "★ YOU WIN" : (winnerP == nil ? "STALEMATE" : "\(winnerP!.name.uppercased()) WINS"))
                .font(.system(size: 30, weight: .medium, design: .monospaced))
                .tracking(8)
                .foregroundColor(iWon ? Color(hex: "#69f0ae") : Color(hex: "#ff3040"))
                .shadow(color: iWon ? Color(hex: "#69f0ae") : Color(hex: "#ff3040"), radius: 20)
            Text("MATCH · OVER").font(.system(size: 10, design: .monospaced)).tracking(6).foregroundColor(.gray)
        }
    }

    func scoreboard(players: [Player], winnerId: String?) -> some View {
        let sorted = players.sorted { ($0.kills, -$0.deaths) > ($1.kills, -$1.deaths) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PLAYER").frame(minWidth: 140, alignment: .leading)
                Text("K").frame(width: 40, alignment: .trailing)
                Text("D").frame(width: 40, alignment: .trailing)
                Text("ACC").frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 10, design: .monospaced)).tracking(2).foregroundColor(Color(hex: "#c8a6ff"))
            .padding(.vertical, 6)

            ForEach(sorted) { p in
                let acc = p.shots > 0 ? Int(Double(p.hits) / Double(p.shots) * 100) : 0
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: p.color)).frame(width: 10, height: 10).shadow(color: Color(hex: p.color), radius: 4)
                        Text(p.name).foregroundColor(p.id == winnerId ? Color(hex: "#69f0ae") : .cyan)
                    }
                    .frame(minWidth: 140, alignment: .leading)
                    Text("\(p.kills)").frame(width: 40, alignment: .trailing).foregroundColor(.cyan)
                    Text("\(p.deaths)").frame(width: 40, alignment: .trailing).foregroundColor(Color(hex: "#ff3040"))
                    Text("\(acc)%").frame(width: 60, alignment: .trailing).foregroundColor(Color(hex: "#e9e3ff"))
                }
                .font(.system(size: 13, design: .monospaced))
                .padding(.vertical, 8)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.cyan.opacity(0.1)), alignment: .bottom)
            }
        }
        .padding()
        .frame(maxWidth: 460)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#1f1838").opacity(0.6)))
        .overlay(IronManPanelBorder())
    }
}
