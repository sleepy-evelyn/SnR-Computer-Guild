-- TODO List
-- # Add Checksum verification for file downloads

LOOP_DELAY_SECS = 4
MAX_LOOPS = 1000
PLAYER_DETECTOR_RANGE = 6
CHECK_TRADE_CYCLE_FREQ = 4

-- Fallback options
FALLBACK_CHANCE = 0.1
FALLBACK_BG_COLOUR = "yellow"

-- Text colours to compliment custom background colour.
-- Black is excluded. Using Blit codes.
COMPLIMENTARY_TEXT_COLOURS = {
    black = "yellow",
    blue = "white",
    gray = "yellow",
    lightGrey = "yellow",
    purple = "yellow",
    red = "yellow",
    green = "white"
}

BANKS_FILE = "https://raw.githubusercontent.com/sleepy-evelyn/SnR-Computer-Guild/refs/heads/main/data/banking/banks.json?t=" .. os.epoch("utc")

_monitor = peripheral.find("monitor")
_entityDetector = peripheral.find("entity_detector")
_inventory = peripheral.find("inventory")
_modem = peripheral.find("modem")
_numTradeOffers = 3

function getEpochMinutes()
    return math.ceil(os.epoch("utc") / 60000)
end

function printWarning(message)
    term.setTextColour(colours.orange)
    print(message)
    term.setTextColour(colours.white)
end

function deepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function readFileFromURL(url)
    local response, statusCode = http.get(url)
    local fileContent = nil

    if not response then
        error("HTTP request failed with status code: " .. statusCode)
    else
        fileContent = response.readAll()
    end

    response.close()
    return fileContent
end

function readJSONFile(fileName)
    if fs.exists(fileName) then
        local file = fs.open(fileName, "r")
        local content = file.readAll()
        local json = textutils.unserializeJSON(content)
        file.close()
        return json
    else
        error("Failed to read " .. fileName)
    end
end

function saveJSONFile(fileName, content, serialize)
    local file = fs.open(fileName, "w")
    if serialize then
        content = textutils.serializeJSON(content)
    end
    file.write(content)
    file.close()
end

function loadTradingPostState()
    local state = nil;

    if fs.exists("state.json") then
        state = readJSONFile("state.json")

        -- State file exists but no settings URL is defined
        if (state.settingsURL == "") then
            printWarning("The state.json file has no valid settings URL. Deleting file and requesting manual input...")
            fs.delete("state.json")
            loadTradingPostState()
        end
    else
        -- Settings file exists but a state file doesn't
        if fs.exists("settings.json") then
            printWarning("A settings.json file exists but a state.json file doesn't. Deleting file and requesting manual input...")
            fs.delete("settings.json")
        end

        state = {
            settingsURL = "",
            nextTrade = -1
        }
        saveJSONFile("state.json", state, true)
    end
    return state
end

function loadSettings(state)
    -- Generate the settings file from a remote URL if it doesn't exist
    if not fs.exists("settings.json") then
        if state.settingsURL == "" then
            term.setTextColour(colours.white)
            print("What is the settings file URL?")
            term.setTextColour(colours.lightBlue)
            state.settingsURL = read()

            while not http.checkURL(state.settingsURL) or not string.find(state.settingsURL, ".json") do
                term.setTextColour(colours.red)
                print("Invalid JSON file link. Please try again...")
                term.setTextColour(colours.lightBlue)
                state.settingsURL = read()
            end
        end

        local settingsFileRemote = readFileFromURL(state.settingsURL)
        if settingsFileRemote then
            saveJSONFile("settings.json", settingsFileRemote, false)
            saveJSONFile("state.json", state, true)
        else
            error("Failed to load the JSON file from this URL. Terminating program...")
        end
    end

    -- Error checking
    local errorMessages = {
        trades = "A list of trades must be included in the settings file",
        tradeCycle = "The settings file must include a trade cycle in minutes",
        maxTradesPerCycle = "The settings file must include a maximum number of trades per cycle"
    }
    local settings = readJSONFile("settings.json")

    for key, message in pairs(errorMessages) do
        if settings[key] == nil then
            error(errorMessages[key])
        end
    end

    -- Declare when the next trade will be if it's not already defined
    if state.nextTrade <= 0 then
        state.nextTrade = getEpochMinutes() + settings.tradeCycle
        saveJSONFile("state.json", state, true)
    end
    return settings
end

function loadBankSettings(settings)
    -- Early return if no bank is linked
    if settings.bank == nil then
        return nil
    end

    local banksFileRemote = readFileFromURL(BANKS_FILE)
    if banksFileRemote then
        local banksFileJson = textutils.unserializeJSON(banksFileRemote)
        local bankSettings = banksFileJson[settings.bank]

        if bankSettings ~= nil then
            if not bankSettings.enabled then
                error("This trading post is linked to a Nation Bank that is currently disabled.")
            else
                local blazeBankerPos = bankSettings.blazeBanker
                if blazeBankerPos ~= nil and #blazeBankerPos == 3 then
                    return bankSettings
                else
                    error("A Blaze Banker position is required since this Trading Post is linked to a Nation Bank.")
                end
            end
        else
            error("This Trading Post is linked to a Nation Bank that doesn't exist.")
        end
    else
        error("The global bank list is missing or cannot be loaded. Please report this to a member of staff.")
    end
end

function logToFile(message)
    local logFile = fs.open("transactions.log", "a")

    if logFile then
        local timestamp = os.date("%H:%M:%S - %Y-%m-%d")
        logFile.write("[" .. timestamp .. "] " .. message .. "\n")
        logFile.close()
        return true
    else
        return false
    end
end

function findClosestPlayer()
	local entities = _entityDetector.nearbyEntities()

    if #entities == 0 then
        return nil
    end

    for i, entity in ipairs(entities) do
        if entity.isPlayer then
            local x = math.abs(entity.x)
            local z = math.abs(entity.z)

            if (x <= PLAYER_DETECTOR_RANGE and z <= PLAYER_DETECTOR_RANGE) then
                return {
                    uuid = entity.uuid,
                    name = entity.name
                }
            end
        end
    end
    return nil
end

function printHeading(bgColourString, bankName)
    local textColour = colours.black

    -- Get the headers text colour
    local complimentaryColour = COMPLIMENTARY_TEXT_COLOURS[bgColourString]
    textColour = colours[complimentaryColour] or colours.black

    _monitor.clear()
    _monitor.setTextColour(textColour)
    _monitor.setBackgroundColour(colours[bgColourString])
    _monitor.setCursorPos(1,1)
    _monitor.setTextScale(0.5)
    if bankName then
        _monitor.write(bankName .. " - Trading Post" .. "                         ")
    else
        _monitor.write("Trading Post                         ")
    end
    _monitor.setCursorPos(1,2)
    _monitor.write("____________________________________")
    _monitor.setBackgroundColour(colours.black)
    _monitor.setTextColour(colours.white)
end

function printTrades(trades, bankSettings)
    local bgColourString = FALLBACK_BG_COLOUR
    local bankName = nil

    if bankSettings then
        bankName = bankSettings.name
        bgColourString = bankSettings.colour or bgColourString
    end
    printHeading(bgColourString, bankName)

    for idx, trade in ipairs(trades) do
        _monitor.setCursorPos(1, idx + 3)
        _monitor.write(("x%d %s - %d¤"):format(trade.amount, trade.name, trade.value))

        if idx == #trades then
            _monitor.setCursorPos(1, #trades + 5)
            _monitor.setTextColour(colours.yellow)
            _monitor.write("Place items in the chest to trade")
            _monitor.setCursorPos(1, #trades + 6)
            _monitor.setTextColour(colours.lightGrey)
            _monitor.write("(¤ = 1 spur)")
        end
    end
end

function printBlacklistWarning(name)
    printHeading("Blacklisted from trading", colours.red)
    _monitor.setCursorPos(1,4)
    _monitor.write("You are blacklisted from trading")
    _monitor.setCursorPos(1,5)
    _monitor.write("here. Contact a member of staff")
    _monitor.setCursorPos(1,6)
    _monitor.write("for details.")
end

function cycleTrades(settings, bankSettings)
    local trades = deepCopy(settings.trades)
    local randomTrades = {}
    local exploredTradesIdxSet = {} -- In index format
    local counter = 0;

    -- Generate random trades
    while #randomTrades < _numTradeOffers do
        local randomIdx = math.random(1, #trades)

        if not exploredTradesIdxSet[randomIdx] then
            local randomTrade = trades[randomIdx]
            local randomChance = randomTrade.chance or FALLBACK_CHANCE

            if math.random() <= randomChance then
                local variation = randomTrade.variation or 0
                local randomCost = randomTrade.value + math.floor(math.random(0, variation * 2) - variation)

                -- Set the cost and sanitize keys that aren't needed
                randomTrade.value = randomCost
                randomTrade.variation = nil
                randomTrade.chance = nil

                randomTrades[#randomTrades + 1] = randomTrade
                exploredTradesIdxSet[randomIdx] = true

                if #randomTrades == #trades then
                    break
                end
            end
        end

        counter = counter + 1
        if counter > MAX_LOOPS then
            break
        end
    end

    -- Save trades
    local state = loadTradingPostState()
    state.trades = randomTrades
    saveJSONFile("state.json", state, true)

    -- Print trades
    printTrades(randomTrades, bankSettings)
    return randomTrades
end

-- Checking connected peripherals
if not _entityDetector then
    error("An Entity Detector must be placed next to the computer to identify the trader")
elseif not _monitor then
    error("A Monitor must be placed next to the computer to display trading costs")
elseif not _inventory then
    error("An block with an inventory must be placed next to the computer to accept trades")
end

_monitor.setPaletteColour(colours.purple, 0x724085)
_monitor.setPaletteColour(colours.red, 0xa40b15)

local state = loadTradingPostState()
local settings = loadSettings(state)
local bankSettings = loadBankSettings(settings) -- Could be Nil
local trades = cycleTrades(settings, bankSettings)

term.setTextColour(colours.lime)
print("Computer is setup for trading!")
term.setTextColour(colours.white)

local counter = 0
while true do
    local player = findClosestPlayer()
    if player ~= nil then
        -- Check if a player is blacklisted
        if settings.blacklist == nil or settings.blacklist[player.uuid] == nil then
            -- TODO
        else
            printBlacklistWarning(player.name)
        end
    end

    if counter > CHECK_TRADE_CYCLE_FREQ then
        local nowMins = getEpochMinutes()

        -- New trade cycle
        if (nowMins > state.nextTrade) then
            state.limits = nil
            state.nextTrade = nowMins + settings.tradeCycle
            trades = cycleTrades(settings, bankSettings)
        end
        counter = 0
    end

    sleep(LOOP_DELAY_SECS)
    counter = counter + 1
end
