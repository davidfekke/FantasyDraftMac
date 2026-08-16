import Foundation
import SwiftData

@Model
final class FantasyPlayer: Identifiable {
    var id: String = ""
    var fullName: String = ""
    var position: String?
    var team: String?
    var teamAbbreviation: String?
    var searchRank: Int?
    var playerID: String?
    var espnID: Int?
    var yahooID: Int?
    var fantasyDataID: Int?
    var rotowireID: Int?
    var age: Int?
    var college: String?
    var yearsExperience: Int?
    var height: String?
    var weight: String?
    var number: Int?
    var status: String?
    var birthDate: String?
    var isPicked: Bool = false
    var generatedSummaryText: String?
    var generatedSummaryUsedFoundationModel: Bool = false
    var generatedSummarySourceNames: [String] = []
    var generatedSummarySourceURLStrings: [String] = []

    init(id: String, fullName: String, draftItem: DraftItem) {
        self.id = id
        self.fullName = fullName
        self.position = draftItem.position
        self.team = draftItem.team
        self.teamAbbreviation = draftItem.teamAbbreviation
        self.searchRank = draftItem.searchRank
        self.playerID = draftItem.playerID
        self.espnID = draftItem.espnID
        self.yahooID = draftItem.yahooID
        self.fantasyDataID = draftItem.fantasyDataID
        self.rotowireID = draftItem.rotowireID
        self.age = draftItem.age
        self.college = draftItem.college
        self.yearsExperience = draftItem.yearsExperience
        self.height = draftItem.height
        self.weight = draftItem.weight
        self.number = draftItem.number
        self.status = draftItem.status
        self.birthDate = draftItem.birthDate
        self.isPicked = false
        self.generatedSummaryText = nil
        self.generatedSummaryUsedFoundationModel = false
        self.generatedSummarySourceNames = []
        self.generatedSummarySourceURLStrings = []
    }

    var displayTeam: String? {
        teamAbbreviation ?? team
    }

    var headshotURL: URL? {
        guard let playerID, !playerID.isEmpty else { return nil }
        return URL(string: "https://sleepercdn.com/content/nfl/players/\(playerID).jpg")
    }

    var profileURLs: [PlayerProfileURL] {
        let slug = fullName.playerProfileSlug
        let fantasyDataSlug = position.map { "\($0.lowercased())/\(slug)" } ?? slug
        var urls: [PlayerProfileURL] = []

        if let playerID, !playerID.isEmpty {
            urls.append(PlayerProfileURL(source: "Sleeper", url: URL(string: "https://sleeper.com/nfl/players/\(slug)-\(playerID)")!))
        }

        if let espnID {
            urls.append(PlayerProfileURL(source: "ESPN", url: URL(string: "https://www.espn.com/nfl/player/_/id/\(espnID)/\(slug)")!))
        }

        if let yahooID {
            urls.append(PlayerProfileURL(source: "Yahoo", url: URL(string: "https://sports.yahoo.com/nfl/players/\(yahooID)/")!))
        }

        if let fantasyDataID {
            urls.append(PlayerProfileURL(source: "FantasyData", url: URL(string: "https://fantasydata.com/nfl/\(fantasyDataSlug)/\(fantasyDataID)")!))
        }

        if let rotowireID {
            urls.append(PlayerProfileURL(source: "Rotowire", url: URL(string: "https://www.rotowire.com/football/player/\(slug)-\(rotowireID)")!))
        }

        return urls
    }

    var storedSummary: PlayerInformationSummary? {
        guard let generatedSummaryText, !generatedSummaryText.isEmpty else { return nil }

        let sourceURLs = zip(generatedSummarySourceNames, generatedSummarySourceURLStrings).compactMap { source, urlString in
            URL(string: urlString).map { PlayerProfileURL(source: source, url: $0) }
        }

        return PlayerInformationSummary(
            text: generatedSummaryText,
            sourceURLs: sourceURLs,
            usedFoundationModel: generatedSummaryUsedFoundationModel
        )
    }

    var summary: String {
        let positionText = position ?? "-"
        let rankText = searchRank.map(String.init) ?? "-"

        if let team, !team.isEmpty {
            return "\(positionText) - \(team): rank \(rankText)"
        }

        return "\(positionText): rank \(rankText)"
    }

    func update(from draftItem: DraftItem, fullName: String) {
        self.fullName = fullName
        self.position = draftItem.position
        self.team = draftItem.team
        self.teamAbbreviation = draftItem.teamAbbreviation
        self.searchRank = draftItem.searchRank
        self.playerID = draftItem.playerID
        self.espnID = draftItem.espnID
        self.yahooID = draftItem.yahooID
        self.fantasyDataID = draftItem.fantasyDataID
        self.rotowireID = draftItem.rotowireID
        self.age = draftItem.age
        self.college = draftItem.college
        self.yearsExperience = draftItem.yearsExperience
        self.height = draftItem.height
        self.weight = draftItem.weight
        self.number = draftItem.number
        self.status = draftItem.status
        self.birthDate = draftItem.birthDate
    }

    func storeSummary(_ summary: PlayerInformationSummary) {
        generatedSummaryText = summary.text
        generatedSummaryUsedFoundationModel = summary.usedFoundationModel
        generatedSummarySourceNames = summary.sourceURLs.map(\.source)
        generatedSummarySourceURLStrings = summary.sourceURLs.map { $0.url.absoluteString }
    }

    func clearDraftState() {
        isPicked = false
        generatedSummaryText = nil
        generatedSummaryUsedFoundationModel = false
        generatedSummarySourceNames = []
        generatedSummarySourceURLStrings = []
    }
}

struct PlayerProfileURL: Hashable, Sendable {
    let source: String
    let url: URL
}

struct DraftItem: Decodable, Sendable {
    let fullName: String?
    let position: String?
    let team: String?
    let teamAbbreviation: String?
    let searchRank: Int?
    let playerID: String?
    let espnID: Int?
    let yahooID: Int?
    let fantasyDataID: Int?
    let rotowireID: Int?
    let age: Int?
    let college: String?
    let yearsExperience: Int?
    let height: String?
    let weight: String?
    let number: Int?
    let status: String?
    let birthDate: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case position
        case team
        case teamAbbreviation = "team_abbr"
        case searchRank = "search_rank"
        case playerID = "player_id"
        case espnID = "espn_id"
        case yahooID = "yahoo_id"
        case fantasyDataID = "fantasy_data_id"
        case rotowireID = "rotowire_id"
        case age
        case college
        case yearsExperience = "years_exp"
        case height
        case weight
        case number
        case status
        case birthDate = "birth_date"
    }
}

private extension String {
    var playerProfileSlug: String {
        folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
