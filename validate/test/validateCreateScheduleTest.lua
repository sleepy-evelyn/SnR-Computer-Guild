local validator = require("validateCreateSchedule")

-- helper methods
local function assertNil(value)
    if value then error("Expected value to be nil but was: " .. tostring(value)) end
end

local function assertSchemaError(err, expectedFormattedError)
    if not err then error("Expected schema error but got nil") end
    local formattedErr = tostring(err)

    if expectedFormattedError then -- only check expectedFormattedError if present
        if formattedErr ~= expectedFormattedError then
            error("Unexpected schema error. Expected error:\n" .. expectedFormattedError ..
                "\nActual error:\n" .. formattedErr)
        end
    end
end

local function deepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in next, orig, nil do
            copy[deepCopy(k)] = deepCopy(v)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- test 1
local schedule1 = {
    progress = 1,
    cyclic = true,
    entries = {
        {
            instruction = {
                data = {
                    text = "Eldmere Station b-SB 2"
                },
                id = "create:destination"
            },
            conditions = {
                {
                    {
                        data = {
                            threshold = "103",
                            measure = 0,
                            operator = 0
                        },
                        id = "createaddition:energy_threshold",
                    },
                },
            },
        },
        {
            instruction = {
                data = {
                    text = "Eldmere Station b-NB 2"
                },
                id = "railways:waypoint_destination"
            },
        },
    },
}
-- correct schema
assertNil(validator.validateCreateSchedule(schedule1))

-- malform schedule: conditions are missing
local schedule1_Neg1 = deepCopy(schedule1)
schedule1_Neg1.entries[1].conditions = nil
assertSchemaError(validator.validateCreateSchedule(schedule1_Neg1),
    "Case failed: Condition 1 of 'conditions' holds but the consequence does not\n" ..
    "  Type mismatch: 'conditions' should be a map (table), is nil")

-- malform schedule: threshold is a number
local schedule1_Neg2 = deepCopy(schedule1)
schedule1_Neg2.entries[1].conditions[1][1].data.threshold = 103
assertSchemaError(validator.validateCreateSchedule(schedule1_Neg2),
    "Case failed: Condition 10 of 'entries.1.conditions.1.1.data' holds but the consequence does not\n" ..
    "  Type mismatch: 'entries.1.conditions.1.1.data.threshold' should be string, is number")

-- malform schedule: condition is not nested enough
local schedule1_Neg3 = deepCopy(schedule1)
local condition = deepCopy(schedule1_Neg3.entries[1].conditions[1][1])
schedule1_Neg3.entries[1].conditions[1][1] = nil
schedule1_Neg3.entries[1].conditions[1] = condition
assertSchemaError(validator.validateCreateSchedule(schedule1_Neg3), nil) -- not checking the giant stacktrace tyvm

-- malform schedule: waypoint instruction has conditions
local schedule1_Neg4 = deepCopy(schedule1)
schedule1_Neg4.entries[2].conditions = schedule1_Neg4.entries[1].conditions
assertSchemaError(validator.validateCreateSchedule(schedule1_Neg4),
    "Case failed: Condition 2 of 'conditions' holds but the consequence does not\n" ..
    "  Type mismatch: 'conditions' should be nil, is table")

-- test 2
local schedule2 = {
    cyclic = true,
    entries = {
        {
            instruction = {
                data = {
                    frequency = {
                        {
                            id = "spelunkery:portal_fluid_bottle",
                            count = 1,
                            tag = {
                                bool = true,
                                anchor_pos = {
                                    x = 103,
                                    y = -330,
                                    z = 584
                                },
                                anchor_dimension = "minecraft:the_nether"
                            },
                        },
                        {
                            count = 1,
                            id = "minecraft:dirt",
                        },
                    },
                    power = 10,
                },
                id = "railways:redstone_link"
            },
        },
    },
}
-- correct schema
assertNil(validator.validateCreateSchedule(schedule2))

-- malform schedule: change instruction.id
local schedule2_Neg1 = deepCopy(schedule2)
schedule2_Neg1.entries[1].instruction.id = "invalid:id"
assertSchemaError(validator.validateCreateSchedule(schedule2_Neg1),
    "No suitable alternative: No schema matches 'entries.1.instruction.id'")

-- malform schedule: negative power
local schedule2_Neg2 = deepCopy(schedule2)
schedule2_Neg2.entries[1].instruction.data.power = -10
assertSchemaError(validator.validateCreateSchedule(schedule2_Neg2),
    "Case failed: Condition 4 of 'entries.1.instruction.data' holds but the consequence does not\n" ..
    "  Invalid value: 'entries.1.instruction.data.power' must be between 1 and 15")

-- malform schedule: item id is missing
local schedule2_Neg3 = deepCopy(schedule2)
schedule2_Neg3.entries[1].instruction.data.frequency[1].id = nil
assertSchemaError(validator.validateCreateSchedule(schedule2_Neg3),
    "Case failed: Condition 4 of 'entries.1.instruction.data' holds but the consequence does not\n" ..
    "  Type mismatch: 'entries.1.instruction.data.frequency.1.id' should be string, is nil")