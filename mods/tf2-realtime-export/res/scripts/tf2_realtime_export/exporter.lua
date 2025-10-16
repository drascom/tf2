local json = require("tf2_realtime_export.json")

local M = {}

local PREFIX = "[TF2ANALYTICS]"
local DEFAULT_INTERVAL = 2.0

local state = {
    interval = DEFAULT_INTERVAL,
    includeCargoBreakdown = true,
    lastExportSimTime = nil,
}

local function tryCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function toIdentifier(value)
    if type(value) == "number" then
        return value
    end

    if type(value) == "table" and value.id then
        return value.id
    end

    return value
end

local function gatherTownData(gameInterface)
    local towns = tryCall(gameInterface.getTowns, gameInterface) or {}
    local summary = {}

    for _, townId in ipairs(towns) do
        local townData = tryCall(gameInterface.getEntity, gameInterface, townId)
        if type(townData) == "table" and townData.town then
            local town = townData.town
            table.insert(summary, {
                id = townId,
                name = townData.name,
                population = town.population,
                targetPopulation = town.targetPopulation,
                cargo = town.cargo,
                growth = town.growth,
            })
        end
    end

    return summary
end

local function gatherIndustryData(gameInterface)
    local industries = tryCall(gameInterface.getIndustries, gameInterface) or {}
    local summary = {}

    for _, industryId in ipairs(industries) do
        local industryData = tryCall(gameInterface.getEntity, gameInterface, industryId)
        if type(industryData) == "table" and industryData.industry then
            local ind = industryData.industry
            table.insert(summary, {
                id = industryId,
                name = industryData.name,
                production = ind.production,
                shipments = ind.shipments,
                transport = ind.transport,
            })
        end
    end

    return summary
end

local function gatherStationData(gameInterface)
    local stations = tryCall(gameInterface.getStations, gameInterface) or {}
    local summary = {}

    for _, stationId in ipairs(stations) do
        local stationData = tryCall(gameInterface.getEntity, gameInterface, stationId)
        if type(stationData) == "table" and stationData.station then
            local waiting = stationData.station and stationData.station.waiting or nil
            if waiting and not state.includeCargoBreakdown then
                waiting = waiting.total or waiting.people or nil
            end

            table.insert(summary, {
                id = stationId,
                name = stationData.name,
                town = toIdentifier(stationData.townEntity),
                waiting = waiting,
            })
        end
    end

    return summary
end

local function gatherLineData(gameInterface)
    local lines = tryCall(gameInterface.getLines, gameInterface) or {}
    local summary = {}

    for _, lineId in ipairs(lines) do
        local lineData = tryCall(gameInterface.getEntity, gameInterface, lineId)
        local stats = tryCall(gameInterface.getLineStats, gameInterface, lineId)
        local vehicles = tryCall(gameInterface.getVehiclesForLine, gameInterface, lineId)

        table.insert(summary, {
            id = lineId,
            name = lineData and lineData.name or nil,
            transportModes = lineData and lineData.transportModes or nil,
            stats = stats,
            vehicles = vehicles,
        })
    end

    return summary
end

local function buildSnapshot(simTime)
    if not game or not game.interface then
        return nil
    end

    local gameInterface = game.interface

    local date = tryCall(gameInterface.getDate, gameInterface)
    local money = tryCall(gameInterface.getFinance, gameInterface)

    local snapshot = {
        simTime = simTime,
        date = date,
        money = money,
        towns = gatherTownData(gameInterface),
        industries = gatherIndustryData(gameInterface),
        stations = gatherStationData(gameInterface),
        lines = gatherLineData(gameInterface),
    }

    return snapshot
end

local function shouldExport(simTime)
    if not simTime then return false end

    if not state.lastExportSimTime then
        return true
    end

    return (simTime - state.lastExportSimTime) >= state.interval
end

function M.init(params)
    state.interval = tonumber(params.interval) or DEFAULT_INTERVAL
    state.includeCargoBreakdown = params.includeCargoBreakdown ~= false
    state.lastExportSimTime = nil
end

local function resolveSimTime(params)
    if type(params) == "number" then
        return params
    end

    if type(params) == "table" then
        return params.simTime or params.time or params[1]
    end

    if game and game.interface then
        return tryCall(game.interface.getGameTime, game.interface)
    end

    return nil
end

function M.update(params)
    local simTime = resolveSimTime(params)

    if not shouldExport(simTime) then
        return
    end

    local snapshot = buildSnapshot(simTime)
    if not snapshot then
        return
    end

    local payload = json.encode(snapshot)
    if payload then
        print(string.format("%s %s", PREFIX, payload))
        state.lastExportSimTime = simTime
    end
end

function M.handleEvent(_, _)
    -- The exporter does not currently react to game events,
    -- but the handler is provided for future extensibility.
end

function M.saveState()
    return {
        lastExportSimTime = state.lastExportSimTime,
        interval = state.interval,
        includeCargoBreakdown = state.includeCargoBreakdown,
    }
end

function M.loadState(saved)
    if type(saved) ~= "table" then return end

    state.lastExportSimTime = saved.lastExportSimTime
    state.interval = saved.interval or state.interval
    state.includeCargoBreakdown = saved.includeCargoBreakdown ~= false
end

return M
