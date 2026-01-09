-- Поместите этот скрипт в папку autoexec вашего эскплойта (Delta, Hydrogen, fluxus и т.д.)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Настройки (должны совпадать с Termux config)
local TERMINAL_IP = "127.0.0.1" -- Localhost работает, так как Termux и Roblox на одном устройстве
local TERMINAL_PORT = 8080

-- Функция отправки Heartbeat через UDP (если поддерживается) или HTTP
-- Большинство Android executor'ов поддерживают request() / http_request()

local function send_heartbeat()
    -- Формируем запрос
    -- Мы используем хак: request на localhost
    -- Многие эксплойты блокируют локалхост, но на андроиде это часто работает.
    -- Если HTTP не работает, можно пробовать WebSocket connect, если есть API.
    
    -- Пробуем HTTP POST (так как UDP сокеты в Ro-Exec обычно недоступны, используем HTTP->UDP бридж или просто HTTP сервер в manager.lua)
    -- В manager.lua мы сделали UDP сервер. Роблокс не умеет слать UDP из коробки через http request.
    -- ИСПРАВЛЕНИЕ: В manager.lua нужно сделать HTTP сервер, или отправлять фейковые запросы. 
    -- НО, LuaSocket в Termux поддерживает UDP, а вот Роблокс HTTP request - это TCP.
    -- Поэтому мы перепишем этот скрипт под простую HTTP логику, но так как я уже написал UDP сервер...
    -- Стоп. Самый надежный способ - HTTP. Я обновлю manager.lua чтобы он слушал TCP HTTP, если это возможно, 
    -- ЛИБО: В Роблоксе нет UDP. 
    -- Решение: Просто используем http_request с методом POST.
    -- В manager.lua надо поменять UDP на TCP сервер или использовать netcat.
    
    -- **IMPORTANT**: Since manager.lua uses UDP in the implementation above, this client wont work directly if `request` only does HTTP (TCP).
    -- However, let's assume valid HTTP support. I will assume the manager.lua needs to be a TCP server or HTTP server.
    -- Actually, writing a robust HTTP server in manager.lua with luasocket is easy.
    
    -- Для данного файла я напишу код, который шлет HTTP запрос.
    -- А manager.lua я сейчас обновлю, чтобы он понимал и TCP/HTTP.
    
    local url = "http://" .. TERMINAL_IP .. ":" .. tostring(TERMINAL_PORT) .. "/"
    
    pcall(function()
        local response = request({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = "alive"
        })
    end)
end

-- Main Loop
spawn(function()
    while true do
        send_heartbeat()
        wait(5) -- Шлем сигнал каждые 5 секунд
    end
end)

print("✅ Autoexec Heartbeat sender started")
