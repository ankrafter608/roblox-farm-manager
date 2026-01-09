-- Config.lua
local config = {}

-- [[ Основные Настройки ]]
config.userId = "123456789" -- Ваш User ID в Roblox
config.placeId = "1234567890" -- ID плейса, в котором должен быть бот
config.vipLink = "roblox://experiences/start?placeId=1234567890" -- Ссылка для входа (можно VIP сервер)
config.packageName = "com.roblox.client" -- Пакет приложения (может быть клон)

-- [[ Настройки Перезапуска ]]
config.checkInterval = 10 -- Как часто проверять статус (секунды)
config.heartbeatTimeout = 60 -- Если скрипт из игры не шлет сигнал столько секунд - перезапуск (Crash/Stuck)
config.apiTimeout = 120 -- Если API роблокса показывает "Offline" столько секунд - перезапуск (Disconnect)
config.bootTime = 45 -- Время на запуск роблокса (пауза после запуска перед проверками)

-- [[ Настройки Сервера ]]
config.serverPort = 8080 -- Порт для приема heartbeats от скрипта в игре
config.webhookUrl = "YOUR_DISCORD_WEBHOOK_URL" -- Ваш вебхук для логов

-- [[ Настройки API ]]
config.checkPresence = true -- Проверять ли статус через Roblox Web API
config.presenceCheckInterval = 30 -- Интервал проверки через API (секунды)

return config
