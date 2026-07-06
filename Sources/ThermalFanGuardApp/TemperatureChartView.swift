import Charts
import SwiftUI
import ThermalFanGuardCore

struct TemperatureChartView: View {
  let history: [HistoryEntry]
  let rules: [GuardRule]

  var body: some View {
  Chart {
      ForEach(rules) { rule in
        RuleMark(y: .value("Trigger", rule.triggerTemperature))
          .foregroundStyle(.orange.opacity(0.35))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          .annotation(position: .top, alignment: .trailing) {
            Text("\(rule.fanSpeedPercent)%")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        RectangleMark(
          yStart: .value("Low", rule.recoveryTemperature),
          yEnd: .value("High", rule.triggerTemperature)
        )
        .foregroundStyle(.orange.opacity(Double(rule.fanSpeedPercent) / 220.0))
      }

      ForEach(points) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("Temperature", point.temperature)
        )
        .interpolationMethod(.catmullRom)
        .foregroundStyle(.red.gradient)
      }
    }
    .chartYScale(domain: yDomain)
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisGridLine()
        AxisValueLabel {
          if let date = value.as(Date.self) {
            Text(date, format: .dateTime.hour().minute())
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading)
    }
    .frame(height: 140)
  }

  private var points: [ChartPoint] {
    history.compactMap { entry in
      guard let temperature = entry.temperature else { return nil }
      return ChartPoint(timestamp: entry.timestamp, temperature: temperature)
    }
  }

  private var yDomain: ClosedRange<Double> {
    let values = points.map(\.temperature)
    let ruleValues = rules.flatMap { [$0.triggerTemperature, $0.recoveryTemperature] }
    let merged = values + ruleValues
    guard let minValue = merged.min(), let maxValue = merged.max() else {
      return 40...100
    }
    return (minValue - 5)...(maxValue + 5)
  }

  private struct ChartPoint: Identifiable {
    let timestamp: Date
    let temperature: Double
    var id: TimeInterval { timestamp.timeIntervalSince1970 }
  }
}
