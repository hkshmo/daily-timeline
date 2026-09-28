import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian
    case english

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: self == .russian ? "ru_RU" : "en_US") }
    var displayName: String { self == .russian ? "Русский" : "English" }
}

struct L10n {
    let language: AppLanguage

    private var ru: Bool { language == .russian }
    var add: String { ru ? "Добавить" : "Add" }
    var today: String { ru ? "Сегодня" : "Today" }
    var emptyTitle: String { ru ? "День свободен" : "Your day is free" }
    var emptyDescription: String { ru ? "Добавьте первый блок на временную линию" : "Add your first block to the timeline" }
    var quit: String { ru ? "Завершить Dayline" : "Quit Dayline" }
    var developer: String { ru ? "Разработчик" : "Developer" }
    var storageErrorTitle: String { ru ? "Ошибка хранения данных" : "Storage error" }
    var storageErrorMessage: String {
        ru
            ? "Dayline сохранил исходные данные, когда это было возможно. Проверьте подробности ниже."
            : "Dayline preserved the original data when possible. Review the details below."
    }
    var edit: String { ru ? "Изменить" : "Edit" }
    var delete: String { ru ? "Удалить" : "Delete" }
    var newBlock: String { ru ? "Новый блок" : "New block" }
    var editBlock: String { ru ? "Изменить блок" : "Edit block" }
    var title: String { ru ? "Название" : "Title" }
    var start: String { ru ? "Начало" : "Start" }
    var end: String { ru ? "Конец" : "End" }
    var color: String { ru ? "Цвет" : "Color" }
    var cancel: String { ru ? "Отмена" : "Cancel" }
    var save: String { ru ? "Сохранить" : "Save" }
    var settings: String { ru ? "Настройки" : "Settings" }
    var languageLabel: String { ru ? "Язык" : "Language" }
    var notifications: String { ru ? "Уведомления о задачах" : "Task notifications" }
    var soundNotifications: String { ru ? "Звуковое уведомление" : "Notification sound" }
    var chooseSound: String { ru ? "Выбрать свой звук…" : "Choose custom sound…" }
    var previewSound: String { ru ? "Прослушать" : "Preview" }
    var systemSound: String { ru ? "Системный звук" : "System sound" }
    var soundFileError: String { ru ? "Не удалось открыть этот аудиофайл" : "Could not open this audio file" }
    var timelineRange: String { ru ? "Временная шкала" : "Timeline range" }
    var from: String { ru ? "С" : "From" }
    var to: String { ru ? "До" : "To" }
    var fullDay: String { ru ? "24 часа" : "24 hours" }
    var workDay: String { ru ? "Рабочий день" : "Workday" }
    var repeatMode: String { ru ? "Повтор" : "Repeat" }
    var everyDay: String { ru ? "Каждый день" : "Every day" }
    var todayOnly: String { ru ? "Разовая" : "One-time" }
    var selectedDays: String { ru ? "По дням" : "Weekdays" }
    var timingMode: String { ru ? "Время" : "Timing" }
    var fixedTime: String { ru ? "По времени" : "Fixed time" }
    var anytime: String { ru ? "В любое время" : "Anytime" }
    var duration: String { ru ? "Длительность" : "Duration" }
    func minutes(_ value: Int) -> String { ru ? "\(value) мин" : "\(value) min" }
    var taskStarted: String { ru ? "Задача началась" : "Task started" }
    var previousTask: String { ru ? "Предыдущая завершена" : "Previous completed" }
    var done: String { ru ? "Готово" : "Done" }
    var snooze: String { ru ? "+5 мин" : "+5 min" }
    var startTask: String { ru ? "Начать" : "Start" }
    var completeTask: String { ru ? "Завершить" : "Complete" }
    var completedTask: String { ru ? "Завершено" : "Completed" }
    var undoCompletion: String { ru ? "Отменить завершение" : "Undo completion" }
    var undoStart: String { ru ? "Отменить начало" : "Undo start" }

    func blocks(_ count: Int) -> String {
        if !ru { return count == 1 ? "1 block" : "\(count) blocks" }
        let mod10 = count % 10
        let mod100 = count % 100
        let word = mod10 == 1 && mod100 != 11 ? "блок" : (2...4).contains(mod10) && !(12...14).contains(mod100) ? "блока" : "блоков"
        return "\(count) \(word)"
    }
}
