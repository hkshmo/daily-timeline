import Foundation

/// Бренд и имя продукта. Меняется в одном месте.
enum AppBrand {
    static let brand = "Moonkite"
    static let product = "Day"
    static var fullName: String { "\(brand) \(product)" }
}

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
    var nowLabel: String { ru ? "Сейчас:" : "Now:" }
    var nextLabel: String { ru ? "Далее:" : "Next:" }
    var nowShort: String { ru ? "Сейчас" : "Now" }
    var nextShort: String { ru ? "Далее" : "Next" }
    var nothingLeftToday: String { ru ? "На сегодня всё" : "Nothing left today" }
    func remaining(_ seconds: TimeInterval) -> String { ru ? "ещё \(duration(seconds))" : "\(duration(seconds)) left" }
    func startsIn(_ seconds: TimeInterval) -> String { ru ? "через \(duration(seconds))" : "in \(duration(seconds))" }
    func at(_ time: String) -> String { ru ? "в \(time)" : "at \(time)" }
    /// «25 мин», «1 ч», «1 ч 5 мин». Округляем вверх, чтобы не показывать «0 мин».
    func duration(_ seconds: TimeInterval) -> String {
        let total = max(1, Int((seconds / 60).rounded(.up)))
        let hours = total / 60
        let minutes = total % 60
        let h = ru ? "ч" : "h"
        let m = ru ? "мин" : "min"
        if hours == 0 { return "\(minutes) \(m)" }
        return minutes == 0 ? "\(hours) \(h)" : "\(hours) \(h) \(minutes) \(m)"
    }
    var emptyTitle: String { ru ? "День свободен" : "Your day is free" }
    var emptyDescription: String { ru ? "Добавьте первый блок на временную линию" : "Add your first block to the timeline" }
    var quit: String { ru ? "Завершить \(AppBrand.fullName)" : "Quit \(AppBrand.fullName)" }
    var developer: String { ru ? "Разработчик" : "Developer" }
    var storageErrorTitle: String { ru ? "Ошибка хранения данных" : "Storage error" }
    var storageErrorMessage: String {
        ru
            ? "\(AppBrand.fullName) сохранил исходные данные, когда это было возможно. Проверьте подробности ниже."
            : "\(AppBrand.fullName) preserved the original data when possible. Review the details below."
    }
    var edit: String { ru ? "Изменить" : "Edit" }
    var delete: String { ru ? "Удалить" : "Delete" }
    var lunch: String { ru ? "Обед" : "Lunch" }
    var warmupTitle: String { ru ? "Время размяться" : "Time to stretch" }
    func warmupMessage(minutes: Int) -> String {
        let time = duration(TimeInterval(minutes * 60))
        return ru
            ? "Вы за компьютером уже \(time) без перерыва. Встаньте, пройдитесь, потянитесь."
            : "You've been at the computer for \(time) without a break. Stand up, walk around, stretch."
    }
    var warmupDone: String { ru ? "Размялся" : "Done" }
    func warmupSnooze(_ minutes: Int) -> String { ru ? "Через \(minutes) мин" : "In \(minutes) min" }
    var warmupReminders: String { ru ? "Напоминать размяться" : "Remind me to stretch" }
    var warmupInterval: String { ru ? "Каждые" : "Every" }
    var warmupHint: String {
        ru
            ? "Перерыв засчитывается сам, если отойти от компьютера на 5 минут, заблокировать экран или во время еды."
            : "A break counts automatically if you step away for 5 minutes, lock the screen, or during a meal."
    }
    var blockType: String { ru ? "Тип" : "Type" }
    var regularTask: String { ru ? "Задача" : "Task" }
    func name(of kind: TaskKind) -> String {
        switch kind {
        case .breakfast: ru ? "Завтрак" : "Breakfast"
        case .lunch: ru ? "Обед" : "Lunch"
        case .dinner: ru ? "Ужин" : "Dinner"
        }
    }
    func addMeal(_ kind: TaskKind) -> String {
        ru ? "Добавить: \(name(of: kind).lowercased())" : "Add \(name(of: kind).lowercased())"
    }
    func mealAlreadyAdded(_ kind: TaskKind, at time: String) -> String {
        ru
            ? "\(name(of: kind)) в \(time) уже добавлен — нажмите, чтобы изменить"
            : "\(name(of: kind)) at \(time) is already added — click to edit"
    }
    var deleteRepeatingTitle: String { ru ? "Удалить повторяющуюся задачу?" : "Delete repeating task?" }
    var deleteOnlyThisDay: String { ru ? "Только этот день" : "Only this day" }
    var deleteThisAndFollowing: String { ru ? "Этот и все следующие дни" : "This and all following days" }
    var deleteWholeSeries: String { ru ? "Все дни, включая прошедшие" : "All days, including past ones" }
    var newBlock: String { ru ? "Новый блок" : "New block" }
    var editBlock: String { ru ? "Изменить блок" : "Edit block" }
    var title: String { ru ? "Название" : "Title" }
    var start: String { ru ? "Начало" : "Start" }
    var end: String { ru ? "Конец" : "End" }
    var color: String { ru ? "Цвет" : "Color" }
    var cancel: String { ru ? "Отмена" : "Cancel" }
    var gotIt: String { ru ? "Понятно" : "Got it" }
    func postponeBy(_ minutes: Int) -> String { ru ? "Отложить на \(minutes) мин" : "Postpone by \(minutes) min" }
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
