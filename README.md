# Dayline

Нативное menu bar приложение для macOS: расписание дня, временная шкала, повторяющиеся задачи, напоминания и локальное хранение данных.

## Требования

- macOS 14 или новее
- Xcode 16 или новее
- Swift 6

## Разработка

Откройте `Dayline.xcodeproj`, выберите схему **Dayline** и нажмите `⌘R`.

Тесты можно запустить командой:

```bash
swift test
```

## Сборка приложения

В Xcode выберите `Product → Archive`, затем `Distribute App → Custom → Copy App`. Полученный `Dayline.app` можно перенести в папку «Программы».

Release-сборка универсальна для Intel и Apple Silicon. Сборка из терминала:

```bash
xcodebuild -project Dayline.xcodeproj -scheme Dayline -configuration Release -destination 'generic/platform=macOS' build
```

## iPhone и синхронизация iCloud

В проекте есть схема **Dayline iOS**. Для iPhone с iOS 27 установите Xcode с поддержкой iOS 27, подключите телефон и включите на нём Developer Mode.

Для CloudKit требуется активное членство Apple Developer Program. В Xcode для targets **Dayline** и **Dayline iOS** откройте `Signing & Capabilities`, выберите свою Team и привяжите контейнер `iCloud.com.hkshmo.dayline`. Затем выберите схему **Dayline iOS**, свой iPhone и нажмите `⌘R`.

Mac и iPhone должны быть авторизованы в одном аккаунте iCloud. Задачи сохраняются локально и синхронизируются через приватную CloudKit-базу; удалённые задачи хранятся как скрытые tombstone-записи, чтобы они не появлялись повторно на другом устройстве.

## Структура

- `App` — точка входа и управление menu bar
- `Models` — модели данных
- `Stores` — состояние, бизнес-логика и сохранение
- `Views` — интерфейс SwiftUI
- `Support` — локализация и общие расширения
- `Resources` — App Icon и ресурсы приложения

Данные хранятся локально в `~/Library/Application Support/Dayline/tasks.json`.

Разработчик: **hkshmo**
