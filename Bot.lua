-- Global Variables
LatestGameState = {}  -- Stores all game data
InAction = false      -- Prevents bot from performing multiple actions concurrently

-- Color Codes for Console Output
colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Calculate Manhattan distance between two points.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @return: Manhattan distance between the two points.
function manhattanDistance(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

-- Move towards a specific target direction.
-- @param player: The player object containing current coordinates.
-- @param target: The target object containing target coordinates.
-- @return: The direction to move towards the target.
function moveToTarget(player, target)
    if target.x > player.x then
        return "Right"
    elseif target.x < player.x then
        return "Left"
    elseif target.y > player.y then
        return "Down"
    elseif target.y < player.y then
        return "Up"
    end
end

-- Decide the next action based on player proximity, energy, health, and game map analysis.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local bestTarget = nil
    local minHealth = math.huge
    local minDistance = math.huge

    -- Find the closest and weakest target within attack range
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            local distance = manhattanDistance(player.x, player.y, state.x, state.y)
            if distance <= 1 and state.health < minHealth then
                minHealth = state.health
                bestTarget = target
                minDistance = distance
            elseif distance <= 1 and state.health == minHealth and distance < minDistance then
                bestTarget = target
                minDistance = distance
            end
        end
    end

    if bestTarget and player.energy > 5 then
        print(colors.red .. "Player in range. Attacking " .. bestTarget .. "." .. colors.reset)
        ao.send({
            Target = Game,
            Action = "PlayerAttack",
            Player = ao.id,
            AttackEnergy = tostring(player.energy),
            TargetPlayer = bestTarget
        })
    else
        -- If health is low, consider retreating or finding a safe place
        if player.health < 20 then
            print(colors.blue .. "Low health. Finding safe place." .. colors.reset)
            local safeDirections = {"Up", "Down", "Left", "Right"}
            local safeDirection = safeDirections[math.random(#safeDirections)]
            ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = safeDirection})
        else
            -- Move towards the weakest target or randomly if no target in range
            if bestTarget then
                local direction = moveToTarget(player, LatestGameState.Players[bestTarget])
                print(colors.blue .. "Moving towards target: " .. direction .. colors.reset)
                ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
            else
                print(colors.red .. "No player in range or low energy. Moving randomly." .. colors.reset)
                local directions = {"Up", "Down", "Left", "Right"}
                local randomDirection = directions[math.random(#directions)]
                ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = randomDirection})
            end
        end
    end
    InAction = false -- Reset the "InAction" flag
end

-- Event Handlers

Handlers.add("PrintAnnouncements", Handlers.utils.hasMatchingTag("Action", "Announcement"), function (msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
        InAction = true
        ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
        print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
end)

Handlers.add("GetGameStateOnTick", Handlers.utils.hasMatchingTag("Action", "Tick"), function ()
    if not InAction then
        InAction = true
        print(colors.gray .. "Getting game state..." .. colors.reset)
        ao.send({Target = Game, Action = "GetGameState"})
    else
        print("Previous action still in progress. Skipping.")
    end
end)

Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"), function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
end)

Handlers.add("UpdateGameState", Handlers.utils.hasMatchingTag("Action", "GameState"), function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print 'LatestGameState' for detailed view.")
end)

Handlers.add("decideNextAction", Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"), function ()
    if LatestGameState.GameMode ~= "Playing" then
        InAction = false
        return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
end)

Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"), function (msg)
    if not InAction then
        InAction = true
        local playerEnergy = LatestGameState.Players[ao.id].energy
        if playerEnergy == nil then
            print(colors.red .. "Unable to read energy." .. colors.reset)
            ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
        elseif playerEnergy == 0 then
            print(colors.red .. "Player has insufficient energy." .. colors.reset)
            ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
        else
            print(colors.red .. "Returning attack." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "PlayerAttack",
                Player = ao.id,
                AttackEnergy = tostring(playerEnergy)
            })
        end
        InAction = false
        ao.send({Target = ao.id, Action = "Tick"})
    else
        print("Previous action still in progress. Skipping.")
    end
end)
