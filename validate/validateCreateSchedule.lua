-- How to use:
-- Place schema.lua in the same directory as this file. You can get schema.lua from the lua-schema repo: https://github.com/sschoener/lua-schema
-- Import this module in your script: `local validator =require(validateCreateSchedule)`
-- Then call the main method to validate your schema: `local err=validator.validateCreateSchedule(schedule)`
-- If the schema is correct, the method will return `nil`
-- Else, it returns a table with all errors in the schema, which you can print with `print(tostring(err))`
-- For examples of errors, see validateCreateScheduleTest.lua

-- Supports instructions and conditions from:
-- * Create
-- * Create: Steam 'n' Rails
-- * Create Crafts & Additions
-- Documentation taken from: https://github.com/Creators-of-Create/Create/wiki/Train-Schedule-(ComputerCraft)

local schema = require("schema")
local this = {}

-- helper validations

local positiveIntegerSchema = schema.AllOf(schema.Integer, schema.PositiveNumber)

local itemInConditionSchema = schema.Record({
    id = schema.String,
    count = 1,
    tag = schema.Optional(schema.Table)
})

-- main validations
local instructionSchema = schema.Record({
    id = schema.String,
    data = schema.Case("id",
        { "create:destination", schema.Record({
            text = schema.String
        }) },
        { "create:rename", schema.Record({
            text = schema.String
        }) },
        { "create:throttle", schema.Record({
            value = schema.AllOf(schema.Integer, schema.NumberFrom(5, 100))
        }) },
        { "railways:redstone_link", schema.Record({
            frequency = schema.Tuple(itemInConditionSchema, itemInConditionSchema),
            power = schema.AllOf(schema.Integer, schema.NumberFrom(1, 15))
        }) },
        { "railways:waypoint_destination", schema.Record({
            text = schema.String
        }) }
    )
})

local conditionSchema = schema.Record({
    id = schema.String,
    data = schema.Case("id",
        { "create:delay", schema.Record({
            value = schema.Integer,
            time_unit = schema.OneOf(0, 1, 2)
        }) },
        { "create:time_of_day", schema.Record({
            hour = schema.AllOf(schema.Integer, schema.NumberFrom(0, 23)),
            minute = schema.AllOf(schema.Integer, schema.NumberFrom(0, 59)),
            rotation = schema.AllOf(schema.Integer, schema.NumberFrom(0, 9))
        }) },
        { "create:fluid_threshold", schema.Record({
            bucket = itemInConditionSchema,
            threshold = positiveIntegerSchema,
            operator = schema.OneOf(0, 1, 2),
            measure = 0
        }) },
        { "create:item_threshold", schema.Record({
            item = itemInConditionSchema,
            threshold = positiveIntegerSchema,
            operator = schema.OneOf(0, 1, 2),
            measure = schema.OneOf(0, 1)
        }) },
        { "create:redstone_link", schema.Record({
            frequency = schema.Tuple(itemInConditionSchema, itemInConditionSchema),
            inverted = schema.OneOf(0, 1)
        }) },
        { "create:player_count", schema.Record({
            count = positiveIntegerSchema,
            exact = schema.OneOf(0, 1)
        }) },
        { "create:idle", schema.Record({
            value = positiveIntegerSchema,
            time_unit = schema.OneOf(0, 1, 2)
        }) },
        { "create:unloaded", schema.Record({}) },
        { "create:powered", schema.Record({}) },
        { "createaddition:energy_threshold", schema.Record({
            threshold = schema.Pattern("-?[0-9][0-9]*"), -- yes it's a string
            operator = schema.OneOf(0, 1, 2),
            measure = 0
        }) },
        { "railways:loaded", schema.Record({}) }
    )
})

local baseConditionsSchema = schema.Map(positiveIntegerSchema, schema.Map(positiveIntegerSchema, schema.Record({
    id = schema.OneOf("create:delay", "create:time_of_day", "create:fluid_threshold", "create:item_threshold",
        "create:redstone_link",
        "create:player_count", "create:idle", "create:unloaded", "create:powered", "createaddition:energy_threshold"),
    data = schema.Optional(schema.Table)
})))

-- does not check instruction.data structure, conditions structure, and if instruction should have condition
local entrySchema1 = schema.Record({
    instruction = schema.Record({
        id = schema.OneOf("create:destination", "create:rename", "create:throttle", "railways:redstone_link",
            "railways:waypoint_destination"),
        data = schema.Table
    }),
    conditions = schema.Optional(schema.Table)
})

-- same as entrySchema2 but now checks if instruction should have condition
local entrySchema2 = schema.Record({
    instruction = schema.Record({
        id = schema.OneOf("create:destination", "create:rename", "create:throttle", "railways:redstone_link",
            "railways:waypoint_destination"),
        data = schema.Table
    }),
    conditions = schema.Case(schema.Path("..", "instruction", "id"),
        { "create:destination", baseConditionsSchema },
        { schema.Test(function(val) return val ~= "create:destination" end), schema.Nil }
    )
})

local scheduleSchema = schema.Record({
    progress = schema.Optional(schema.PositiveNumber),
    cyclic = schema.Optional(schema.Boolean),
    entries = schema.Map(positiveIntegerSchema, entrySchema1)
})

-- run validation

local function addError(errMsg, err)
    if not err then return errMsg end
    if not errMsg then
        errMsg = err
    else
        errMsg:append(err)
    end
    return errMsg
end

local function changeErrorMessage(error, from, to)
    if not error then return error end
    if error.message then
        error.message = error.message:gsub(from, to)
    end
    if error.suberrors then
        for _, sub in pairs(error.suberrors) do
            changeErrorMessage(sub, from, to)
        end
    end
    return error
end

-- hack to get more descriptive error messages by modifying schema.Error.message
local function changeErrorListMessage(list, from, to)
    if not list then return list end
    for _, error in pairs(list) do
        changeErrorMessage(error, from, to)
    end
    return list
end

function this.validateCreateSchedule(schedule)
    local err = schema.CheckSchema(schedule, scheduleSchema)
    if err then return err end

    local errors = nil
    -- check if instructions and conditions match
    -- check instructions individually
    for i, entry in ipairs(schedule.entries) do
        err = schema.CheckSchema(entry, entrySchema2)
        if err then
            --       err = changeErrorListMessage(err, "data", "entries." .. i .. ".instruction.data")
            errors = addError(err)
        end

        err = schema.CheckSchema(entry.instruction, instructionSchema)
        if err then
            err = changeErrorListMessage(err, "data", "entries." .. i .. ".instruction.data")
            errors = addError(err)
        end
    end

    -- check conditions individually
    for i, entry in ipairs(schedule.entries) do
        if entry.conditions then -- == orList
            for j, andList in ipairs(entry.conditions) do
                for k, condition in ipairs(andList) do
                    err = schema.CheckSchema(condition, conditionSchema)
                    if err then
                        err = changeErrorListMessage(err, "data",
                            "entries." .. i .. ".conditions." .. j .. "." .. k .. ".data")
                        errors = addError(err)
                    end
                end
            end
        end
    end

    return errors
end

return this
