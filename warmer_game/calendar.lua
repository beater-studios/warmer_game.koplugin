-- Pattern "daily". This file is copied unchanged into every
-- plugin with a daily challenge, as <id>/calendar.lua: change the pattern first, then copy it again.
--
-- The day count of a daily challenge and what goes with it: the item of the day, a free pick that skips the
-- items of the coming days, and the streak. Everyone on the same calendar day gets the same day number,
-- whatever the time zone or daylight saving time, with no internet needed.
local Calendar = {}

-- Day 0 is 2026-01-01. Changing it changes the item of every day and the day numbers players share.
Calendar.EPOCH_DAY = 20454

-- Civil date ({ year, month, day }) to a day count, with no time involved (Howard Hinnant's days_from_civil).
function Calendar.day_number(date)
    local year = date.month <= 2 and date.year - 1 or date.year
    local era = math.floor(year / 400)
    local year_of_era = year - era * 400
    local shifted_month = date.month > 2 and date.month - 3 or date.month + 9
    local day_of_year = math.floor((153 * shifted_month + 2) / 5) + date.day - 1
    local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year
    return era * 146097 + day_of_era - 719468 - Calendar.EPOCH_DAY
end

-- Today in the device's local calendar.
function Calendar.today()
    return Calendar.day_number(os.date("*t"))
end

-- The item of a day: the list is walked in order and starts over at the end. Growing the list at the end
-- keeps the item of past days only while the day number is below the old length; after the list has
-- wrapped, any change of length moves the item of every following day. nil for an empty list.
function Calendar.of_day(list, day)
    if #list == 0 then
        return nil
    end
    return list[day % #list + 1]
end

-- How strongly pick_free avoids an item, in the set built by `avoided`: a recent free game, a coming daily,
-- today's daily. A set built elsewhere with true values counts as today's.
local RANK = { recent = 1, upcoming = 2, today = 3 }

-- A set with the items of today and of the `upcoming` days after it, compared through key(item) (the item
-- itself by default, or for example the word without accents), plus the values in `recent` as they are.
-- Each value is "today", "upcoming" or "recent", so a test like avoided[x] still works.
function Calendar.avoided(list, today, upcoming, recent, key)
    local set = {}
    for _, value in ipairs(recent or {}) do
        set[value] = "recent"
    end
    if #list == 0 then
        return set
    end
    for day = today + upcoming, today, -1 do
        local item = Calendar.of_day(list, day)
        set[key and key(item) or item] = day == today and "today" or "upcoming"
    end
    return set
end

-- A random item for free play that is not in `avoided`. When every item is avoided, recent games come back
-- first, then the coming days; today's item only when the list has nothing else. random(n) returns an
-- integer from 1 to n, like math.random. nil for an empty list.
function Calendar.pick_free(list, avoided, random, key)
    if #list == 0 then
        return nil
    end
    local candidates
    for limit = 0, 3 do
        candidates = {}
        for _, item in ipairs(list) do
            local mark = avoided[key and key(item) or item]
            if not mark or (RANK[mark] or 3) <= limit then
                candidates[#candidates + 1] = item
            end
        end
        if #candidates > 0 then
            break
        end
    end
    return candidates[random(#candidates)]
end

-- Daily results kept as counters: played, won, streak, best_streak and the last day recorded. The plugin may
-- keep more fields in the same table.
function Calendar.new_stats()
    return { played = 0, won = 0, streak = 0, best_streak = 0, last_day = nil }
end

-- Records the result of a day once. Returns true when it was recorded, so the plugin adds its own counts
-- (attempts, hints) only then; false when that day or a later one was already recorded (a clock set
-- backwards would otherwise count the same days twice).
function Calendar.record(stats, day, won)
    if stats.last_day and day <= stats.last_day then
        return false
    end
    stats.played = stats.played + 1
    if won then
        stats.won = stats.won + 1
        stats.streak = stats.last_day == day - 1 and stats.streak + 1 or 1
        stats.best_streak = math.max(stats.best_streak, stats.streak)
    else
        stats.streak = 0
    end
    stats.last_day = day
    return true
end

-- The saved streak only changes when a day is recorded, so a missed day is checked when showing it. A today
-- before the last recorded day (clock set backwards) keeps the saved streak.
function Calendar.current_streak(stats, today)
    if stats.last_day and today - stats.last_day > 1 then
        return 0
    end
    return stats.streak
end

-- For results kept by day ({ [day] = result }): the days in a row with a result, ending today or yesterday.
function Calendar.streak_of(results, today)
    local day = results[today] and today or today - 1
    local count = 0
    while results[day] do
        count = count + 1
        day = day - 1
    end
    return count
end

return Calendar
