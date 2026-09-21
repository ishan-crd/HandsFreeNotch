//
//  NotchView.swift
//  HandsFreeNotch
//
//  Notch shape adapted from NotchOS (https://github.com/ishan-crd/NotchOS). MIT License.
//

import HandsFreeNotchCore
import SwiftUI

struct NotchView: View {
    @Bindable var vm: NotchViewModel

    var body: some View {
        ZStack(alignment: .top) {
            notchShape
            content
                .frame(width: vm.notchSize.width, height: vm.notchSize.height)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(vm.animation, value: vm.notchSize)
        .animation(vm.animation, value: vm.status == .opened)
        .preferredColorScheme(.dark)
    }

    // MARK: - Shape

    private var notchShape: some View {
        Color.black
            .mask(mask)
            .frame(width: vm.notchSize.width + vm.cornerRadius * 2, height: vm.notchSize.height)
            .shadow(color: .black.opacity(vm.status == .opened || vm.pipelineState != .idle ? 0.6 : 0), radius: 14, y: 4)
    }

    private var mask: some View {
        Rectangle()
            .frame(width: vm.notchSize.width, height: vm.notchSize.height)
            .clipShape(.rect(bottomLeadingRadius: vm.cornerRadius, bottomTrailingRadius: vm.cornerRadius))
            .overlay(alignment: .topLeading) {
                Fillet().fill(.black)
                    .frame(width: vm.cornerRadius, height: vm.cornerRadius)
                    .offset(x: -vm.cornerRadius + 0.5, y: -0.5)
            }
            .overlay(alignment: .topTrailing) {
                Fillet().fill(.black)
                    .scaleEffect(x: -1)
                    .frame(width: vm.cornerRadius, height: vm.cornerRadius)
                    .offset(x: vm.cornerRadius - 0.5, y: -0.5)
            }
    }

    /// The concave flare joining the notch's side to the menu bar.
    private struct Fillet: Shape {
        func path(in rect: CGRect) -> Path {
            let r = min(rect.width, rect.height)
            var p = Path()
            p.move(to: .zero)
            p.addArc(center: CGPoint(x: 0, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: r, y: 0))
            p.closeSubpath()
            return p
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.status == .opened {
            PanelView(vm: vm)
                .padding(.top, vm.hardwareNotch.height)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        } else {
            switch vm.pipelineState {
            case .idle:
                EmptyView()
            case let .listening(transcript):
                let hint = vm.pipeline.continuous ? "Listening — tap \(vm.settings.hotkey.title) or say stop" : "Listening…"
                pill(icon: "mic.fill", tint: .red, text: transcript.isEmpty ? hint : transcript, dim: transcript.isEmpty) {
                    LevelBars(level: vm.level)
                }
            case let .thinking(transcript):
                pill(icon: "sparkles", tint: .purple, text: transcript, dim: false) {
                    ProgressView().controlSize(.mini).tint(.white)
                }
            case let .done(title, tier, ms):
                pill(icon: "checkmark.circle.fill", tint: .green, text: title, dim: false) {
                    Text("\(ms) ms · \(tier.rawValue)")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            case let .failed(message):
                pill(icon: "exclamationmark.triangle.fill", tint: .orange, text: message, dim: false) { EmptyView() }
            case let .agent(goal, lines):
                agentCard(goal: goal, lines: lines)
                    .padding(.top, vm.hardwareNotch.height)
            case .help:
                HelpView(compact: true)
                    .padding(12)
                    .padding(.top, vm.hardwareNotch.height)
            }
        }
    }

    /// Icon and text on the left of the physical notch, the trailing view on its right; the
    /// middle is the camera housing and stays empty.
    private func pill<Trailing: View>(icon: String, tint: Color, text: String, dim: Bool, @ViewBuilder trailing: () -> Trailing) -> some View {
        let isFailure = icon.hasPrefix("exclamationmark")
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(text)
                    .font(.system(size: isFailure ? 10.5 : 12, weight: .medium))
                    .foregroundStyle(.white.opacity(dim ? 0.5 : 0.92))
                    .lineLimit(isFailure ? 2 : 1)
                    .truncationMode(isFailure ? .tail : .head)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(width: vm.sideWidth)
            Color.clear.frame(width: vm.hardwareNotch.width)
            HStack {
                trailing()
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(width: vm.sideWidth)
        }
        .transition(.opacity)
        .id(text)
    }

    private func agentCard(goal: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Agent · \(goal)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button("Stop") { vm.pipeline.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
            }
            ForEach(Array(lines.suffix(5).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
