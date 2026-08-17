import SwiftUI

struct StageSettingsPopover: View {
  @ObservedObject var state: AppState

  private let ink = Color(red: 0.92, green: 0.93, blue: 0.94)
  private let muted = Color(red: 0.62, green: 0.64, blue: 0.67)
  private let accent = Color(red: 1, green: 0.23, blue: 0.19)

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Stage")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(muted)
        .textCase(.uppercase)
        .tracking(0.5)
        .padding(.bottom, 4)

      ForEach(CanvasStage.allCases) { stage in
        Button {
          state.stage = stage
        } label: {
          HStack(spacing: 10) {
            StageSwatch(stage: stage)
            VStack(alignment: .leading, spacing: 1) {
              Text(stage.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink)
              Text(stage.blurb)
                .font(.system(size: 11))
                .foregroundStyle(muted)
            }
            Spacer(minLength: 8)
            if state.stage == stage {
              Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 7)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(state.stage == stage ? Color.white.opacity(0.08) : Color.clear)
          )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .frame(width: 260)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(red: 0.14, green: 0.14, blue: 0.15))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
  }
}

private struct StageSwatch: View {
  let stage: CanvasStage

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(stage.fill)
      if stage == .checker {
        CheckerMini()
      }
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(Color.white.opacity(0.88))
        .padding(7)
    }
    .frame(width: 36, height: 26)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    )
  }
}

private struct CheckerMini: View {
  var body: some View {
    Canvas { context, size in
      let tile: CGFloat = 5
      let dark = Color(red: 0.17, green: 0.17, blue: 0.18)
      let light = Color(red: 0.28, green: 0.28, blue: 0.30)
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))
      let cols = Int(ceil(size.width / tile))
      let rows = Int(ceil(size.height / tile))
      for row in 0..<rows {
        for col in 0..<cols where (row + col).isMultiple(of: 2) {
          context.fill(
            Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
            with: .color(light)
          )
        }
      }
    }
  }
}
