local exporter = require("tf2_realtime_export.exporter")

function data()
    return {
        init = function(self, params)
            exporter.init(params or {})
        end,
        update = function(self, params)
            exporter.update(params or {})
        end,
        handleEvent = function(self, eventId, data)
            exporter.handleEvent(eventId, data)
        end,
        save = function()
            return exporter.saveState()
        end,
        load = function(data)
            exporter.loadState(data)
        end,
    }
end

return data
