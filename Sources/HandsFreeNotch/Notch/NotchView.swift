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
        .offset(x: vm.horizontalOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Width follows the words as they arrive, so the resize must be quick and never bounce.
        .animation(vm.status == .opened ? vm.animation : .easeOut(duration: 0.14), value: vm.notchSize)
        .animation(vm.animation, value: vm.status == .opened)
        .preferredColorScheme(.dark)
    }

    // MARK: - Shape

    private var notchShape: some View {
        Color.black
            .mask(mask)
            .frame(width: vm.notchSize.width + vm.cornerRadius * 2, height: vm.notchSize.height)
            .shadow(color: .black.opacity(vm.status == .opened ? 0.6 : (vm.pipelineState != .idle ? 0.3 : 0)), radius: vm.status == .opened ? 14 : 8, y: 3)
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
                pill(icon: "mic.fill", tint: .red, dim: transcript.isEmpty, head: true) {
                    LevelBars(level: vm.level)
                }
            case .thinking:
                pill(icon: "sparkles", tint: .purple, dim: false, head: false) {
                    ProgressView().controlSize(.mini).tint(.white)
                }
            case let .done(_, tier, ms):
                pill(icon: "checkmark.circle.fill", tint: .green, dim: false, head: false) {
                    Text("\(ms) ms")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(tier == .fast ? .green.opacity(0.8) : .white.opacity(0.45))
                }
            case .failed:
                pill(icon: "exclamationmark.triangle.fill", tint: .orange, dim: false, head: false) { EmptyView() }
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

    /// Icon and text left of the camera housing; the text continues on the right strip when it
    /// is long, followed by the indicator. The housing itself stays empty.
    private func pill<Trailing: View>(icon: String, tint: Color, dim: Bool, head: Bool, @ViewBuilder trailing: () -> Trailing) -> some View {
        let layout = vm.pill
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(layout.leftText)
                    .font(Font(layout.font))
                    .foregroundStyle(.white.opacity(dim ? 0.5 : 0.92))
                    .lineLimit(1)
                    .truncationMode(head ? .head : .tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(width: layout.left)
            Color.clear.frame(width: vm.hardwareNotch.width)
            HStack(spacing: 8) {
                if !layout.rightText.isEmpty {
                    Text(layout.rightText)
                        .font(Font(layout.font))
                        .foregroundStyle(.white.opacity(dim ? 0.5 : 0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.leading, layout.rightText.isEmpty ? 0 : 8)
            .padding(.trailing, PillLayout.trailingPadding)
            .frame(width: layout.right)
        }
        .transition(.opacity)
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
