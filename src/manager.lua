local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("cjson") 
local config_default = require("config")

-- Пытаемся загрузить сохраненный конфиг, иначе используем дефолтный
local config = config_default
local CONFIG_FILE = "settings.json"

local function load_saved_config()
    local f = io.open(CONFIG_FILE, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content and content ~= "" then
            local status, saved = pcall(json.decode, content)
            if status and saved then
                for k,v in pairs(saved) do
                    config[k] = v
                end
            end
        end
    end
end

local function save_config()
    local f = io.open(CONFIG_FILE, "w")
    if f then
        f:write(json.encode(config))
        f:close()
    end
end

load_saved_config()

-- [[ ANSI Colors ]]
local colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m",
    bold = "\27[1m"
}

-- [[ Helper Functions ]]
local function clear()
    os.execute("clear")
end

local function print_header()
    clear()
    print(colors.magenta .. colors.bold .. [[
  ____       _     _             
 |  _ \ ___ | |__ | | _____  __  
 | |_) / _ \| '_ \| |/ _ \ \/ /  
 |  _ < (_) | |_) | | (_) >  <   
 |_| \_\___/|_.__/|_|\___/_/\_\  
                                 
    ]] .. colors.cyan .. "Manager v1.0 | Status: " .. colors.green .. "Active" .. colors.reset)
    print(colors.blue .. string.rep("-", 40) .. colors.reset)
end

local function input(prompt)
    io.write(colors.yellow .. prompt .. colors.reset)
    return io.read()
end

-- [[ Logic State ]]
local state = {
    status = "INIT", -- INIT, RUNNING, RESTARTING, BROKEN
    lastHeartbeat = 0,
    lastApiCheck = 0,
    lastPresenceStatus = true,
    isBooting = false,
    logs = {},
    bootEndTime = 0
}

local function add_log(msg)
    local timestamp = os.date("%H:%M:%S")
    local fullMsg = string.format("[%s] %s", timestamp, msg)
    table.insert(state.logs, 1, fullMsg) -- Add to start
    if #state.logs > 10 then table.remove(state.logs) end -- Keep last 10
    
    -- Webhook (Async-ish check done via blocking call currently, should be careful)
    -- Для TUI лучше не блокировать экран надолго, поэтому вебхук лучше слать через корутину или быстро
    -- В данном примере оставим как есть, но это может фризить UI на полсекунды
end

-- [[ Run Shell ]]
local function run_shell(cmd)
    os.execute("su -c '" .. cmd .. "'")
end

-- [[ Package Manager ]]
local function get_roblox_packages()
    local packages = {}
    -- Используем pm list packages для получения всех пакетов
    -- так как мы уже под root (tsu), прав достаточно
    local handle = io.popen("pm list packages")
    if handle then
        for line in handle:lines() do
            -- формат вывода: package:com.android.chrome
            local pkg = line:match("package:(.*)")
            if pkg then
                -- Фильтруем: ищем "roblox" или похожие на стандартный клиент паттерны
                -- Клоны часто называют com.roblox.clienu, com.roblox.client1 и т.д.
                if pkg:lower():match("roblox") then
                    table.insert(packages, pkg)
                end
            end
        end
        handle:close()
    end
    table.sort(packages)
    return packages
end

-- [[ Logic Functions ]]
local function restart_roblox(reason)
    add_log("⚠️ RESTARTING: " .. reason)
    state.status = "RESTARTING"
    
    local pkg = config.packageName or "com.roblox.client"
    run_shell("am force-stop " .. pkg)
    socket.sleep(1) 
    
    local startCmd = string.format("am start -a android.intent.action.VIEW -d \"%s\"", config.vipLink)
    -- Некоторые клоны могут требовать явного указания пакета для интента, если их несколько
    -- Но обычно система сама предлагает или выбирает дефолтный. 
    -- Чтобы точно запустить ИМЕННО ЭТОТ клон, добавляем -p <package>
    startCmd = startCmd .. " -p " .. pkg
    
    run_shell(startCmd)
    
    add_log("✅ Launch command sent (" .. pkg .. ")")
    state.lastHeartbeat = os.time() + config.bootTime
    state.bootEndTime = os.time() + config.bootTime
    state.lastPresenceStatus = true
    state.isBooting = true
end

local function parse_presence_response(response_text)
    local success, data = pcall(json.decode, response_text)
    if success and data and data.userPresences and data.userPresences[1] then
        local p = data.userPresences[1]
        -- 0=Offline, 1=Online, 2=InGame, 3=Studio
        if p.userPresenceType == 2 then
            return true, "InGame"
        elseif p.userPresenceType == 1 then
            return false, "Online (Not InGame)"
        else
            return false, "Offline"
        end
    end
    return false, "API/Parse Error"
end

local function check_roblox_api()
    local url = "https://presence.roblox.com/v1/presence/users"
    local body_json = json.encode({userIds = {tonumber(config.userId)}})
    
    -- Проверяем наличие SSL. Если нет - используем cURL (есть почти везде в Termux)
    local ssl_avail = pcall(require, "ssl")

    if ssl_avail then
        -- Используем LuaSocket + LuaSec
        local response_body = {}
        local res, code = http.request({
            url = url,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#body_json)
            },
            source = ltn12.source.string(body_json),
            sink = ltn12.sink.table(response_body)
        })
        
        if code == 200 then
            return parse_presence_response(table.concat(response_body))
        end
    else
        -- Fallback: Используем системный curl
        -- Экранируем кавычки для shell команд (простой вариант для json без спецсимволов)
        local cmd = string.format("curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s'", body_json, url)
        local handle = io.popen(cmd)
        if handle then
            local result = handle:read("*a")
            handle:close()
            if result and result ~= "" then
                 return parse_presence_response(result)
            end
        end
    end
    
    return false, "Connection Error"
end

-- [[ Dashboard ]]
local function draw_dashboard()
    clear() 
    print(colors.magenta .. "╔══════════════════════════════════════╗")
    print("║ " .. colors.bold .. colors.white .. "       ROBLOX FARM MONITOR        " .. colors.magenta .. "║")
    print("╚══════════════════════════════════════╝" .. colors.reset)
    
    print("")
    print(colors.cyan .. " Account Status:" .. colors.reset)
    print("  User ID:    " .. colors.white .. config.userId)
    print("  App Pkg:    " .. colors.white .. config.packageName)
    print("  Place ID:   " .. colors.white .. config.placeId)
    
    local statusColor = colors.green
    if state.status == "RESTARTING" then statusColor = colors.yellow end
    if state.status == "BROKEN" then statusColor = colors.red end
    
    print("  Status:     " .. statusColor .. state.status .. colors.reset)
    
    if state.isBooting then
        local remaining = state.bootEndTime - os.time()
        print("  Booting:    " .. colors.yellow .. remaining .. "s remaining" .. colors.reset)
    end

    print("")
    print(colors.cyan .. " Metrics:" .. colors.reset)
    local hbAgo = os.time() - state.lastHeartbeat
    if state.isBooting then hbAgo = 0 end
    local hbColor = (hbAgo < 15) and colors.green or colors.red
    print("  Last Heartbeat: " .. hbColor .. hbAgo .. "s ago" .. colors.reset)
    
    print("")
    print(colors.cyan .. " Recent Logs:" .. colors.reset)
    print(colors.blue .. string.rep("-", 40) .. colors.reset)
    for i, logMsg in ipairs(state.logs) do
        if i <= 5 then
            print(" " .. colors.white .. logMsg .. colors.reset)
        end
    end
    print(colors.blue .. string.rep("-", 40) .. colors.reset)
    print(colors.bold .. "PRESS CTRL+C TO STOP" .. colors.reset)
end

-- [[ Main Logic Loop ]]
local function start_monitoring()
    -- Init Server
    local server = socket.bind("0.0.0.0", config.serverPort)
    server:settimeout(0.01) -- Very short timeout for non-blocking
    
    add_log("🚀 Manager started on port " .. config.serverPort)
    state.status = "RUNNING"
    state.lastHeartbeat = os.time()
    
    while true do
        local currentTime = os.time()
        
        -- 1. Heartbeat Check
        local client = server:accept()
        if client then
            client:settimeout(0.1)
            local line, err = client:receive()
            if not err then
                client:send("HTTP/1.1 200 OK\r\n\r\n")
                if state.isBooting then
                    add_log("🟢 Connected! Boot phase complete.")
                    state.isBooting = false
                    state.status = "RUNNING"
                end
                state.lastHeartbeat = currentTime
            end
            client:close()
        end
        
        -- 2. Logic
        if not state.isBooting then
            -- Heartbeat Timeout
            if (currentTime - state.lastHeartbeat) > config.heartbeatTimeout then
                restart_roblox("No heartbeat for " .. (currentTime - state.lastHeartbeat) .. "s")
            end
            
            -- API Check
            if config.checkPresence and (currentTime - state.lastApiCheck) > config.presenceCheckInterval then
                local isOnline, statusText = check_roblox_api()
                state.lastApiCheck = currentTime
                
                if not isOnline then
                    if (currentTime - state.lastPresenceStatus) > config.apiTimeout then
                       restart_roblox("API Offline: " .. statusText) 
                    end
                else
                    state.lastPresenceStatus = currentTime
                end
            end
        else
            -- Check boot timeout
            if currentTime > state.bootEndTime then
                 -- Boot time over, assume running if logic passes next tick
                 state.isBooting = false
            end
        end
        
        -- 3. Update UI
        draw_dashboard()
        socket.sleep(1) -- Refresh rate 1s
    end
end

-- [[ Menus ]]
local function menu_settings()
    while true do
        clear()
        print(colors.magenta .. " [[ SETTINGS ]] " .. colors.reset)
        print("1. User ID:   " .. colors.green .. config.userId .. colors.reset)
        print("2. Place ID:  " .. colors.green .. config.placeId .. colors.reset)
        print("3. VIP Link:  " .. colors.green .. (config.vipLink:sub(1,30).."...") .. colors.reset)
        print("4. App Pkg:   " .. colors.green .. (config.packageName or "com.roblox.client") .. colors.reset)
        print("5. Webhook:   " .. colors.green .. (config.webhookUrl == "YOUR_DISCORD_WEBHOOK_URL" and "Not Set" or "Set") .. colors.reset)
        print("0. Back")
        print("")
        
        local choice = input("Select option > ")
        
        if choice == "1" then
            config.userId = input("New User ID: ")
            save_config()
        elseif choice == "2" then
            config.placeId = input("New Place ID: ")
            save_config()
        elseif choice == "3" then
            config.vipLink = input("New VIP Link: ")
            save_config()
        elseif choice == "4" then
             print(colors.cyan .. "\nScanning packages... (looking for *roblox*)" .. colors.reset)
             local pkgs = get_roblox_packages()
             if #pkgs == 0 then
                 print(colors.red .. "No roblox packages found automatically." .. colors.reset)
                 print("Enter manually?")
                 if input("[y/n] > ") == "y" then
                      config.packageName = input("Package Name (e.g com.roblox.client): ")
                      save_config()
                 end
             else
                 print("\nFound Packages:")
                 for i, p in ipairs(pkgs) do
                     print(string.format("%d. %s", i, p))
                 end
                 print("Enter number to select, or 'm' for manual entry")
                 local sel = input("> ")
                 local num = tonumber(sel)
                 if num and pkgs[num] then
                     config.packageName = pkgs[num]
                     save_config()
                     print(colors.green .. "Selected: " .. pkgs[num] .. colors.reset)
                     socket.sleep(1)
                 elseif sel == 'm' then
                     config.packageName = input("Package Name: ")
                     save_config()
                 end
             end
        elseif choice == "5" then
            config.webhookUrl = input("New Webhook URL: ")
            save_config()
        elseif choice == "0" then
            break
        end
    end
end

local function main_menu()
    while true do
        print_header()
        print("")
        print(colors.green .. "1. Start Farm" .. colors.reset)
        print(colors.blue .. "2. Settings" .. colors.reset)
        print(colors.red .. "0. Exit" .. colors.reset)
        print("")
        
        local choice = input("Select option > ")
        
        if choice == "1" then
            start_monitoring()
        elseif choice == "2" then
            menu_settings()
        elseif choice == "0" then
            os.exit()
        end
    end
end

-- Start
main_menu()
