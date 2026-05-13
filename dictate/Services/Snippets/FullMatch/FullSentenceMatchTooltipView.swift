import SwiftUI

struct FullSentenceMatchTooltipView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("When to enable full sentence match")
        .font(.headline)

      Text("Use full match for replacement where the text to replace is the entire sentence you dictated")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      FullSentenceUseCaseCard(
        title: "Use case: \"address\"",
        badge: "ON",
        badgeColor: .green,
        primaryLine: "\"address\" -> \"123 rue du blé\"",
        secondaryLine: "\"What's your address ?\" -> \"What's your address ?\"",
        secondaryIcon: "xmark.circle"
      )

      FullSentenceUseCaseCard(
        title: "Use case: \"pro signature\"",
        badge: "OFF",
        badgeColor: .orange,
        primaryLine: "\"pro signature\" -> \"Cyprien Ricque, Dev\"",
        secondaryLine: "\"... regards, pro signature\" -> \"... regards, Cyprien Ricque, Dev\"",
        secondaryIcon: "checkmark.circle"
      )
    }
  }
}

struct FullSentenceUseCaseCard: View {
  let title: String
  let badge: String
  let badgeColor: Color
  let primaryLine: String
  let secondaryLine: String
  let secondaryIcon: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(title)
          .font(.subheadline.weight(.semibold))

        Text(badge)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(
            Capsule(style: .continuous)
              .fill(badgeColor.opacity(0.16))
          )
          .overlay(
            Capsule(style: .continuous)
              .stroke(badgeColor.opacity(0.4), lineWidth: 1)
          )
      }

      Label(primaryLine, systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(.primary)

      Label(secondaryLine, systemImage: secondaryIcon)
        .font(.caption)
        .foregroundStyle(.primary)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }
}


#Preview {
  FullSentenceMatchTooltipView()
    .padding()
}
