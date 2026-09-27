import SwiftUI

extension TaskColor {
    var swiftUIColor: Color {
        switch self {
        case .blue: .blue
        case .violet: .purple
        case .orange: .orange
        case .green: .green
        case .pink: .pink
        case .red: .red
        case .cyan: .cyan
        case .teal: .teal
        case .yellow: .yellow
        case .indigo: .indigo
        case .mint: .mint
        case .brown: .brown
        }
    }
}
