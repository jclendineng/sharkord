import SwiftUI

// the app's few speeds, named for what moves rather than how long it takes, so two things
// doing the same job move alike. a gesture's own follow through, tuned against the finger,
// keeps its numbers beside the gesture
enum Motion {
    // a control answering a tap: a button swapped for another, a row lighting, a badge
    static var quick: Animation { .snappy(duration: 0.2) }
    // something that moves or changes size: a list reordering, a bar sliding in, a card growing
    static var standard: Animation { .smooth(duration: 0.3) }
    // a panel taking the keyboard's place or a card coming up over the conversation
    static var panel: Animation { .spring(response: 0.35, dampingFraction: 0.9) }
    // only opacity changing, nothing moving
    static var fade: Animation { .easeOut(duration: 0.15) }
    // something lifting or settling under a pointer or a finger, with no bounce to it
    static var press: Animation { .spring(response: 0.25, dampingFraction: 1) }
}

// the corners that have to match from one screen to the next
enum Radius {
    // a picture or a file in a message, a tile in a grid of them
    static var media: CGFloat { 8 }
    // a button drawn as a filled box
    static var control: CGFloat { 10 }
    // a card, a menu or a notice floating over the content
    static var card: CGFloat { 12 }
}
