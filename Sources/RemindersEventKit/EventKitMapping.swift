import EventKit
import RemindersCore

extension ReminderListDTO {
  init(_ calendar: EKCalendar, incompleteCount: Int) {
    self.init(
      id: calendar.calendarIdentifier,
      title: calendar.title,
      sourceTitle: calendar.source?.title ?? "",
      incompleteCount: incompleteCount
    )
  }
}
