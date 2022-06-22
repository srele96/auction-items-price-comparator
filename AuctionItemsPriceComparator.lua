SLASH_APC1 = "/apc"
SlashCmdList["APC"] = function(msg)
    if msg == "run" then
        AuctionItemsPriceComparatorCORE.Run()
    elseif msg == "stop" then
        AuctionItemsPriceComparatorCORE.Stop()
    elseif msg == "tojsonarr" then
        AuctionItemsPriceComparatorCORE.ToJSONArray()
    elseif msg == "tojsonobj" then
        AuctionItemsPriceComparatorCORE.ToJSONObject()
    end
end

local _, core = ...

local JsonHandler = {
    GetKeyValue = function(self, key, value)
        return '"' .. key .. '":' .. '"' .. value .. '"'
    end,

    ItemToJson = function(self, item)
        local nameKeyValue = self:GetKeyValue("name", item.name)
        local countKeyValue = self:GetKeyValue("count", item.count)
        local gold = self:GetKeyValue("gold", item.gold)
        local silver = self:GetKeyValue("silver", item.silver)
        local copper = self:GetKeyValue("copper", item.copper)

        return '{' .. nameKeyValue .. ',' .. countKeyValue .. ',' .. gold .. ',' .. silver .. ',' .. copper .. '}'
    end,

    TableToJsonArray = function(self, table)
        local jsonArray = ""

        for i, item in pairs(table) do
            jsonArray = jsonArray .. self:ItemToJson(item) .. ","
        end

        return "[" .. jsonArray:sub(1, -2) .. "]"
    end,

    TableToJsonObject = function(self, table)
        local jsonObject = ""

        for i, item in pairs(table) do
            jsonObject = jsonObject .. '"' .. item.name .. '":' .. self:ItemToJson(item) .. ","
        end

        return "{" .. jsonObject:sub(1, -2) .. "}"
    end,

    SaveTabletoDBAsJSONArray = function(self)
        local itemsJSON = self:TableToJsonArray(AuctionItemsPriceComparatorDB[GetRealmName()].items)
        AuctionItemsPriceComparatorDB[GetRealmName()].itemsJSONArray = itemsJSON
    end,

    SaveTabletoDBAsJSONObject = function(self)
        local itemsJSONObject = self:TableToJsonObject(AuctionItemsPriceComparatorDB[GetRealmName()].items)
        AuctionItemsPriceComparatorDB[GetRealmName()].itemsJSONObject = itemsJSONObject
    end
}

local ScriptMessages = {
    Start = "Started Querying auction...",
    End = "Stopped Querying auction.",
    Complete = "Completed querying items.",

    QueryingPage = function(self, index, totalPages)
        return "Saving page [ " .. index .. " / " .. totalPages .. " ] item data..."
    end
}

-- TODO: Check if this utility class makes gold, silver or copper non existing values
-- maybe i need to use tonumber?
local PriceConverter = {
    GetGold = function(self, buyoutPrice)
        local buyoutPriceStr = tostring(buyoutPrice)
        local len = strlen(buyoutPriceStr)

        return strsub(buyoutPriceStr, 1, len - 4)
    end,

    GetSilver = function(self, buyoutPrice)
        return strsub(tostring(buyoutPrice), -4, -3)
    end,

    GetCopper = function(self, buyoutPrice)
        return strsub(tostring(buyoutPrice), -2, -1)
    end
}

local ItemsCollection = {
    PriceConverter = PriceConverter,

    AddItem = function(self, item)
        local existingItem = self:GetItemFromRealmDB(item.name)

        if existingItem then
            local newItemCheaper = self:GetEachItemPrice(item) < self:GetEachItemPrice(existingItem)

            if newItemCheaper then
                self:WriteItemToRealmDB(item)
            end
        else
            self:WriteItemToRealmDB(item)
        end
    end,

    WriteItemToRealmDB = function(self, item)
        AuctionItemsPriceComparatorDB[GetRealmName()].items[item.name] = item
    end,

    GetItemFromRealmDB = function(self, itemName)
        return AuctionItemsPriceComparatorDB[GetRealmName()].items[itemName]
    end,

    GetEachItemPrice = function(self, item)
        return item.gold / item.count
    end,

    CreateItem = function(self, name, count, buyoutPrice)
        local gold = PriceConverter:GetGold(buyoutPrice)
        local silver = PriceConverter:GetSilver(buyoutPrice)
        local copper = PriceConverter:GetCopper(buyoutPrice)

        return {
            name = name,
            count = count,
            gold = gold,
            silver = silver,
            copper = copper
        }
    end
}

local PagesHandlingData = {
    currentPageIndex = 0,
    totalPages = -1,

    IsLastPage = function(self)
        return self.currentPageIndex == self.totalPages
    end,

    NextPage = function(self)
        self.currentPageIndex = self.currentPageIndex + 1
    end,

    SetTotalPages = function(self)
        local pageTotalItems, queryTotalItems = GetNumAuctionItems("list")
        self.totalPages = math.floor(queryTotalItems / 50)
    end
}

local QueryHandler = {
    PagesHandlingData = PagesHandlingData,
    ScriptMessages = ScriptMessages,

    queryingEnabled = false,

    EnableQuerying = function(self)
        self.queryingEnabled = true
    end,

    DisableQuerying = function(self)
        self.queryingEnabled = false
    end,

    QueryNextPage = function(self)
        local canQuery = CanSendAuctionQuery("list")

        if self.queryingEnabled and canQuery then
            -- if not self.PagesHandlingData:IsLastPage() then
                QueryAuctionItems("", nil, nil, nil, nil, nil, self.PagesHandlingData.currentPageIndex)
                self.PagesHandlingData:NextPage()
                print(self.ScriptMessages:QueryingPage(self.PagesHandlingData.currentPageIndex,
                    self.PagesHandlingData.totalPages))
            -- else
                -- self:DisableQuerying()
                -- print(self.ScriptMessages.Complete)
            -- end
        end
    end
}

local PageHandler = {
    ItemsCollection = ItemsCollection,
    PagesHandlingData = PagesHandlingData,

    lastQueriedPageIndex = nil,

    PageUpdated = function(self)
        -- prevent querying same page twice, for some reason triggers more than once for same page
        local isNewPage = self.lastQueriedPageIndex ~= self.PagesHandlingData.currentPageIndex

        if isNewPage then
            self.lastQueriedPageIndex = self.PagesHandlingData.currentPageIndex

            self.PagesHandlingData:SetTotalPages()
            self:MapPageItems()
        end
    end,

    MapPageItems = function(self)
        local pageTotalItems, __ = GetNumAuctionItems("list")

        for i = 1, pageTotalItems do
            local name, __, count, quality, __, __, __, __, buyoutPrice = GetAuctionItemInfo("list", i)

            local commonOrBetterQuality = quality >= 1
            -- double quote in name creates problem when parsing JSON
            local nameContainsDoubleQuotes = name:find('"', 1, true) ~= nil

            if commonOrBetterQuality and (not nameContainsDoubleQuotes) then
                local newItem = self.ItemsCollection:CreateItem(name, count, buyoutPrice)
                self.ItemsCollection:AddItem(newItem)
            end
        end
    end
}

local AddonDBInitializer = {
    InitializeAddonDB = function(self)
        if AuctionItemsPriceComparatorDB == nil then
            AuctionItemsPriceComparatorDB = {}
        end
    end,

    InitializeRealmDB = function(self)
        local realmName = GetRealmName()

        if AuctionItemsPriceComparatorDB[realmName] == nil then
            AuctionItemsPriceComparatorDB[realmName] = {}
        end
    end,

    InitializeRealmItemsDB = function(self)
        local realmName = GetRealmName()

        if AuctionItemsPriceComparatorDB[realmName].items == nil then
            AuctionItemsPriceComparatorDB[realmName].items = {}
        end
    end
}

AuctionItemsPriceComparatorCORE = {
    QueryHandler = QueryHandler,
    PageHandler = PageHandler,
    ScriptMessages = ScriptMessages,
    AddonDBInitializer = AddonDBInitializer,
    JsonHandler = JsonHandler,

    Run = function()
        AuctionItemsPriceComparatorCORE.QueryHandler:EnableQuerying()
        print(AuctionItemsPriceComparatorCORE.ScriptMessages.Start)
    end,

    Stop = function()
        AuctionItemsPriceComparatorCORE.QueryHandler:DisableQuerying()
        print(AuctionItemsPriceComparatorCORE.ScriptMessages.End)
    end,

    ToJSONArray = function()
        AuctionItemsPriceComparatorCORE.JsonHandler:SaveTabletoDBAsJSONArray()
    end,

    ToJSONObject = function()
        AuctionItemsPriceComparatorCORE.JsonHandler:SaveTabletoDBAsJSONObject()
    end
}

function core:handleEvents(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "AuctionItemsPriceComparator" then
        -- Order of calling is important, first initialize DB then RealmDB
        AuctionItemsPriceComparatorCORE.AddonDBInitializer:InitializeAddonDB()
        AuctionItemsPriceComparatorCORE.AddonDBInitializer:InitializeRealmDB()
        AuctionItemsPriceComparatorCORE.AddonDBInitializer:InitializeRealmItemsDB()

        print("AuctionItemsPriceComparator loaded.")
        print("Available commands:")
        print("/apc run - Scans items from auction house")
        print("/apc stop - Stops scanning items from auction house")
        print("/apc tojsonarr - Stores items as array of objects to JSON string")
        print("/apc tojsonobj - Stores items as object to JSON string")
    end

    if event == "AUCTION_ITEM_LIST_UPDATE" or event == "CHAT_MSG_CHANNEL" then
        -- TODO: fix bug where total pages are set to 0 before query is ran
        AuctionItemsPriceComparatorCORE.PageHandler:PageUpdated()
        -- AuctionItemsPriceComparatorCORE.PageHandler:PageUpdated()
        -- CHAT_MSG_CHANNEL event is frequent enough to trigger query next page
        -- it's not perfect solution but I must wait .3 seconds to query next page
        -- there is no event when querying again is possible
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" or event == "CHAT_MSG_CHANNEL" then
        -- TODO: fix bug where total pages are set to 0 before query is ran
        -- makes queryNextPage stuck and never send query
        AuctionItemsPriceComparatorCORE.QueryHandler:QueryNextPage()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("CHAT_MSG_CHANNEL")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", core.handleEvents)

-- TODO: Lag when saving the JSON array
-- try to save items incrementally, not the whole string chunk at once
-- try to save items as json in one loop when looking up prices
