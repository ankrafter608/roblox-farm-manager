# Roblox Farm Manager (Android/Termux)

Скрипт мониторинга и авто-перезагрузки Roblox для ферм на Android (UgPhone, Vmos и т.д.).

## Требования
1. **Root права** (на UgPhone они есть по умолчанию).
2. **Termux**.
3. **Roblox Executor** (Delta, Hydrogen и др.) с поддержкой `autoexec` и функции `request`.

## Установка

### 1. Настройка Termux
Откройте Termux и введите следующие команды для установки Lua и зависимостей:

```bash
pkg update && pkg upgrade
pkg install tsu lua54
# Устанавливаем LuaRocks (менеджер пакетов Lua) если его нет, или ставим пакеты вручную.
# Но в Termux часто проще скачать готовые so файлы или использовать luarocks.
pkg install luarocks
luarocks install luasocket
luarocks install lua-cjson
```
*Если возникают ошибки с компиляцией cjson/socket, поищите готовые пакеты для Termux: `pkg install lua-cjson` (может не быть в основном репо, тогда придется билдить).*

### 2. Установка скриптов
1. Создайте папку для бота, например `roblox_manager`.
2. Скопируйте туда файлы `manager.lua` и `config.lua` из папки `src`.
3. Отредактируйте `config.lua`:
   - Вставьте свой `userId`
   - `placeId`
   - `webhookUrl` (для Discord логов)
   - `vipLink` (Ссылка, которая открывает нужную игру. Формат: `roblox://experiences/start?placeId=...`)

### 3. Настройка Roblox Executor
1. Скопируйте содержимое файла `src/autoexec.lua`.
2. Создайте новый файл в папке `autoexec` вашего экзекутора (в памяти телефона это обычно `/storage/emulated/0/Android/data/com.roblox.client/...` или папка Delta/Hydrogen в корне).
3. Назовите его, например, `z_heartbeat.lua`.

## Запуск
1. Запустите Termux.
2. Перейдите в папку со скриптом.
3. Запустите:
```bash
tsu
lua54 manager.lua
```

## Использование
После запуска вы увидите интерактивное меню:
1. **Start Farm**: Запускает мониторинг и переходит в режим "Дашборда" (таблички со статусом).
2. **Settings**: Позволяет изменить настройки (UserID, ссылку на VIP сервер и т.д.) прямо в терминале. Настройки сохраняются автоматически.
3. **Exit**: Выход.

В режиме Дашборда скрипт показывает:
- Текущий статус (Online/Restarting).
- Время последнего "пульса" от игры.
- Последние логи событий (рестарты, проверки).
- Нажмите `Ctrl+C` чтобы остановить.

## Решение проблем
- **"Lua module socket not found"**: Значит `luasocket` не установился. Проверьте `luarocks install luasocket`.
- **Bot перезапускает игру даже если я в ней**: Возможно, скрипт `autoexec.lua` не работает внутри игры (эксплойт не поддерживает `request` на localhost). Попробуйте увеличить таймауты в конфиге.
