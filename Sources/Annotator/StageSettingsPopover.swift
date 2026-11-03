import SwiftUI

struct StageSettingsPopover: View {
  @ObservedObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Stage")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)

      ForEach(CanvasStage.allCases) { stage in
        Button {
          state.stage = stage
        } label: {
          HStack(spacing: 10) {
            StageSwatch(stage: stage)
            VStack(alignment: .leading, spacing: 1) {
              Text(stage.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
              Text(stage.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if state.stage == stage {
              Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(state.stage == stage ? Color.primary.opacity(0.08) : Color.clear)
          )
          .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.title). \(stage.blurb)")
      }
    }
    .padding(10)
    .frame(width: 268)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
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
        .fill(Color.white.opacity(0.92))
        .padding(7)
    }
    .frame(width: 36, height: 26)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
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
