import FinalApproachCore
import SwiftUI

/// One line about the light at a spot or a place, such as when golden hour
/// is.
struct LightLine: Identifiable, Equatable {
    let title: String
    let text: String

    var id: String { title }
}

/// The words for a day's light at a spot or a place. The light itself is
/// worked out by `Sunlight` in the core package.
enum SpotLight {
    /// How a time of day is written, such as "5:31 PM".
    static let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)

    /// The day that holds a moment, from its first moment to the next
    /// day's.
    static func day(holding moment: Date, in calendar: Calendar) -> TimeWindow {
        let start = calendar.startOfDay(for: moment)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return TimeWindow(start: start, end: end)
    }

    /// The lines a page shows for a day's light.
    ///
    /// - Parameter looksOneWay: True when the spot says which way a
    ///   photographer faces. Only then can the page say when the sun is
    ///   behind them.
    static func lines(for light: DayLight, looksOneWay: Bool, time: Date.FormatStyle) -> [LightLine] {
        var lines: [LightLine] = []
        if looksOneWay {
            lines.append(LightLine(title: "Sun behind you", text: text(for: light.sunBehind, time: time)))
        }
        lines.append(LightLine(title: "Golden hour", text: text(for: light.goldenHours, time: time)))
        if let sunrise = light.sunrise {
            lines.append(LightLine(title: "Sunrise", text: sunrise.formatted(time)))
        }
        if let sunset = light.sunset {
            lines.append(LightLine(title: "Sunset", text: sunset.formatted(time)))
        }
        return lines
    }

    /// Stretches of time in words, such as "7:03 AM to 7:56 AM". A day
    /// with none says so.
    static func text(for windows: [TimeWindow], time: Date.FormatStyle) -> String {
        guard !windows.isEmpty else { return "Not today" }
        return windows
            .map { "\($0.start.formatted(time)) to \($0.end.formatted(time))" }
            .joined(separator: ", ")
    }
}

/// The light at a spot or a place today, which is when golden hour is and,
/// for a spot that says which way it looks, when the sun is behind the
/// photographer.
struct SpotLightSection: View {
    let point: Coordinate
    /// The compass direction a photographer faces there, or nil when the
    /// place does not say.
    let viewBearing: Double?

    @Environment(SpotsModel.self) private var spots
    @State private var lines: [LightLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading("Light today")
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(line.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 8)
                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Worked out from where the sun is, with clear skies in mind. Times are in this phone's time zone.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .task(id: point) {
            let day = SpotLight.day(holding: Date.now, in: Calendar.current)
            let light = Sunlight.light(
                at: point,
                from: day.start,
                to: day.end,
                viewBearing: viewBearing,
                rules: spots.lightRules
            )
            lines = SpotLight.lines(for: light, looksOneWay: viewBearing != nil, time: SpotLight.timeStyle)
        }
    }
}
