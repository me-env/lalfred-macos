import SwiftUI


enum Tabs: Hashable, CaseIterable {
  case home
  case model
  case textInsertion
  case dictionary
  case snippets
  case sounds
  case account

  var title: String {
    switch self {
    case .home:
      "General"
    case .model:
      "Model"
    case .textInsertion:
      "Text Insertion"
    case .dictionary:
      "Dictionary"
    case .snippets:
      "Snippets"
    case .sounds:
      "Sounds"
    case .account:
      "Account"
    }
  }

  var systemImage: String {
    switch self {
    case .home:
      "gearshape"
    case .model:
      "waveform"
    case .textInsertion:
      "text.cursor"
    case .dictionary:
      "book"
    case .snippets:
      "text.bubble"
    case .sounds:
      "speaker.wave.2"
    case .account:
      "person.crop.circle"
    }
  }

  var selectedSystemImage: String {
    switch self {
    case .home:
      "gearshape.fill"
    case .model:
      "waveform"
    case .textInsertion:
      "text.cursor"
    case .dictionary:
      "book.fill"
    case .snippets:
      "text.bubble.fill"
    case .sounds:
      "speaker.wave.2.fill"
    case .account:
      "person.crop.circle.fill"
    }
  }

  var iconColor: Color {
    switch self {
    case .home:
      Color(red: 0.55, green: 0.55, blue: 0.58)
    case .model:
      Color(red: 1.0, green: 0.58, blue: 0.20)
    case .textInsertion:
      Color(red: 0.20, green: 0.70, blue: 0.62)
    case .dictionary:
      Color(red: 0.44, green: 0.32, blue: 0.90)
    case .snippets:
      Color(red: 0.44, green: 0.32, blue: 0.90)
    case .sounds:
      Color(red: 0.96, green: 0.36, blue: 0.42)
    case .account:
      Color(red: 0.24, green: 0.58, blue: 1.0)
    }
  }
}

