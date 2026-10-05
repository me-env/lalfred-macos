import SwiftUI


/// The transcription model and its parameters.
struct ModelTabView: View {
  var body: some View {
    VStack {
      TranscriptionSection()
    }
    .padding([.bottom, .horizontal])
    .textFieldStyle(.roundedBorder)
  }
}
