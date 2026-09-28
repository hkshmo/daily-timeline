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

## Структура

- `App` — точка входа и управление menu bar
- `Models` — модели данных
- `Stores` — состояние, бизнес-логика и сохранение
- `Views` — интерфейс SwiftUI
- `Support` — локализация и общие расширения
- `Resources` — App Icon и ресурсы приложения

Данные хранятся локально в `~/Library/Application Support/Dayline/tasks.json`.

Разработчик: **hkshmo**
