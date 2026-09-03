import ImeTimeCore

enum HomeRoute: Hashable {
    case createRoom
    case joinRoom
    case room(Room)
    case roomSettings(Room)
}
