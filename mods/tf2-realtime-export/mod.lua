local EXPORT_SCRIPT = "tf2_realtime_export/game_script"

local function translate(text)
    if type(_) == "function" then
        return _(text)
    end
    return text
end

local function info()
    return {
        name = translate("Realtime analytics exporter"),
        description = translate("Streams periodic snapshots of lines, towns, stations and industries through the stdout log."),
        minorVersion = 0,
        severityAdd = "NONE",
        severityRemove = "NONE",
        tags = { "Script" },
        authors = {
            {
                name = "OpenAI gpt-5-codex",
                role = "CREATOR",
            },
        },
        params = {
            {
                key = "exportInterval",
                name = translate("Snapshot interval (seconds)"),
                values = {
                    { "1", translate("1 s") },
                    { "2", translate("2 s") },
                    { "3", translate("3 s") },
                    { "5", translate("5 s") },
                    { "10", translate("10 s") },
                },
                defaultIndex = 2,
            },
            {
                key = "includeCargoBreakdown",
                name = translate("Include cargo wait breakdown"),
                values = {
                    { "true", translate("Yes") },
                    { "false", translate("No") },
                },
                defaultIndex = 1,
            },
        },
    }
end

local function runFn(settings)
    local exportInterval = tonumber(settings.exportInterval) or 2
    local includeCargoBreakdown = settings.includeCargoBreakdown ~= "false"

    if type(addGameScript) ~= "function" then
        print("[TF2ANALYTICS] addGameScript is unavailable; the exporter script could not be registered.")
        return
    end

    addGameScript(EXPORT_SCRIPT, {
        interval = exportInterval,
        includeCargoBreakdown = includeCargoBreakdown,
    })
end

function data()
    return {
        info = info(),
        runFn = runFn,
    }
end

return data
