import SwiftUI

struct ChoiceButton: View {
    let choice: PuzzleChoice
    let isSelected: Bool
    let isRevealed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(choice.san)
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                )
        }
        .disabled(isRevealed)
    }

    private var backgroundColor: Color {
        if !isRevealed { return Color(.secondarySystemBackground) }
        if choice.isCorrect { return Color.green.opacity(0.2) }
        if isSelected { return Color.red.opacity(0.2) }
        return Color(.secondarySystemBackground)
    }

    private var foregroundColor: Color {
        if !isRevealed { return .primary }
        if choice.isCorrect { return .green }
        if isSelected { return .red }
        return .secondary
    }

    private var borderColor: Color {
        if !isRevealed { return Color(.separator) }
        if choice.isCorrect { return .green }
        if isSelected { return .red }
        return Color(.separator)
    }
}
