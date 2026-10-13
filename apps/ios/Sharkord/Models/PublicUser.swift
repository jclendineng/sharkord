import Foundation

enum UserStatus: String, Codable {
    case online
    case idle
    case offline
}

struct PublicUser: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let profileColor: String
    let bio: String?
    let avatar: SharkordFile?
    var status: UserStatus?
    let roleIds: [Int]
}
