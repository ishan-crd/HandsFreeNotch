//
//  LevelBars.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import SwiftUI

/// Five bars that follow the microphone level. Driven by the level updates themselves (about
/// 20 a second) rather than a display-rate timer, so nothing animates while nobody is talking.
struct LevelBars: View {
    var level: Float
    var color: Color = .white

    private static let weights: [CGFloat] = [0.55, 0.85, 1.0, 0.75, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 3 + 11 * CGFloat(level) * Self.weights[i])
            }
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
