//
//  NFLTeam.swift
//  Fantasy Draft
//
//  Created by David Fekke on 8/23/26.
//

enum NFLTeam: String, CaseIterable {
    case ARI, ATL, BAL, BUF
    case CAR, CHI, CIN, CLE
    case DAL, DEN, DET, GB
    case HOU, IND, JAX, KC
    case LAC, LAR, LV, MIA
    case MIN, NE, NO, NYG
    case NYJ, PHI, PIT, SEA
    case SF, TB, TEN, WAS

    var byeWeek: Int {
        switch self {
        case .CAR, .KC:
            return 5

        case .CIN, .DET, .MIA, .MIN:
            return 6

        case .BUF, .JAX, .LAC, .WAS:
            return 7

        case .HOU, .NO, .NYG, .SF:
            return 8

        case .PIT, .TEN:
            return 9

        case .CHI, .DEN, .PHI, .TB:
            return 10

        case .ATL, .CLE, .GB, .LAR, .NE, .SEA:
            return 11

        case .BAL, .IND, .LV, .NYJ:
            return 13

        case .ARI, .DAL:
            return 14
        }
    }
}
