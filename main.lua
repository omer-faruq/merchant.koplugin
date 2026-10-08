local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local MerchantGame = require("merchant_game")
local Themes = require("merchant_themes")
local _ = require("merchant_l10n")
local T = require("ffi/util").template

local Screen = Device.screen

-- ============================================================= game screen ===

local MerchantScreen = InputContainer:extend{}

function MerchantScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.content_width = math.floor(Screen:getWidth() * 0.92)
    self:buildLayout()
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
    -- A turn left unfinished in a previous session (an enemy encounter or a
    -- pending offer) is resolved once the board is on screen.
    if self.game.pending and not self.game.game_over then
        UIManager:nextTick(function()
            self:handlePending()
        end)
    end
end

function MerchantScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    local content_size = self.layout:getSize()
    local offset_x = x + math.floor((self.dimen.w - content_size.w) / 2)
    local offset_y = y + math.floor((self.dimen.h - content_size.h) / 2)
    if offset_y < y then offset_y = y end
    self.layout:paintTo(bb, offset_x, offset_y)
end

function MerchantScreen:statusText()
    local g = self.game
    local lines = {
        T(_("Day %1 / %2          %3"), g.day, MerchantGame.MAX_DAYS, g.location),
        T(_("Cash %1     Bank %2     Debt %3"), g:money(g.cash), g:money(g.bank), g:money(g.debt)),
        T(_("Health %1     %2 %3     %4 %5/%6"),
            g.health, g.theme.weapon_label, g.weapons,
            g.theme.capacity_label, g:spaceUsed(), g.capacity),
    }
    return table.concat(lines, "\n")
end

function MerchantScreen:marketText()
    local g = self.game
    local lines = { g.theme.market_title }
    for i, good in ipairs(g:getGoods()) do
        local price = g.prices[i] and g:money(g.prices[i]) or _("(none)")
        local held = g.inventory[i] or 0
        local held_str = held > 0 and T(_("  [you hold %1]"), held) or ""
        lines[#lines + 1] = T("%1 — %2%3", good.name, price, held_str)
    end
    return table.concat(lines, "\n")
end

function MerchantScreen:buildLayout()
    local face = Font:getFace("smallinfofont")
    self.status_box = TextBoxWidget:new{
        text = self:statusText(),
        face = Font:getFace("infofont"),
        width = self.content_width,
        alignment = "center",
    }
    self.market_box = TextBoxWidget:new{
        text = self:marketText(),
        face = face,
        width = self.content_width,
        alignment = "left",
    }

    local theme = self.game.theme
    local actions = ButtonTable:new{
        width = self.content_width,
        shrink_unneeded_width = false,
        buttons = {
            {
                { text = _("Buy"),  callback = function() self:onBuy() end },
                { text = _("Sell"), callback = function() self:onSell() end },
                { text = theme.travel_label, callback = function() self:onTravel() end },
            },
            {
                { text = theme.lender_label, callback = function() self:onLender() end },
                { text = theme.bank_label,   callback = function() self:onBank() end },
            },
            {
                { text = _("New game"), callback = function() self:onNewGame() end },
                { text = _("Close"),    callback = function() self:onCloseButton() end },
            },
        },
    }

    self.layout = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Size.span.vertical_large },
        FrameContainer:new{
            padding = Size.padding.default,
            bordersize = Size.border.window,
            self.status_box,
        },
        VerticalSpan:new{ width = Size.span.vertical_large },
        FrameContainer:new{
            padding = Size.padding.large,
            bordersize = Size.border.thin,
            self.market_box,
        },
        VerticalSpan:new{ width = Size.span.vertical_large },
        actions,
        VerticalSpan:new{ width = Size.span.vertical_large },
    }
    self[1] = self.layout
end

function MerchantScreen:refresh()
    self:buildLayout()
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function MerchantScreen:save()
    if self.plugin then
        self.plugin:saveState()
    end
end

function MerchantScreen:info(text)
    UIManager:show(InfoMessage:new{ text = text })
end

-- ----------------------------------------------------------------- trading --

function MerchantScreen:onBuy()
    local g = self.game
    local rows = {}
    for i, good in ipairs(g:getGoods()) do
        if g:hasPrice(i) then
            local idx = i
            rows[#rows + 1] = { {
                text = T("%1 — %2", good.name, g:money(g.prices[i])),
                callback = function()
                    UIManager:close(self._dialog)
                    self:promptBuy(idx)
                end,
            } }
        end
    end
    if #rows == 0 then
        self:info(_("Nothing is for sale here."))
        return
    end
    rows[#rows + 1] = { { text = _("Cancel"), callback = function() UIManager:close(self._dialog) end } }
    self._dialog = ButtonDialog:new{ title = _("Buy what?"), title_align = "center", buttons = rows }
    UIManager:show(self._dialog)
end

function MerchantScreen:promptBuy(i)
    local g = self.game
    local good = g:getGoods()[i]
    local max = g:maxBuy(i)
    if max < 1 then
        self:info(_("You can't afford any, or you have no room left."))
        return
    end
    UIManager:show(SpinWidget:new{
        title_text = T(_("Buy %1"), good.name),
        info_text = T(_("%1 each · cash %2 · room %3"), g:money(g.prices[i]), g:money(g.cash), g:spaceLeft()),
        value = max,
        value_min = 1,
        ok_always_enabled = true,
        value_max = max,
        value_step = 1,
        value_hold_step = 10,
        ok_text = _("Buy"),
        callback = function(spin)
            local ok, err = g:buy(i, spin.value)
            if not ok then
                self:info(err or _("Couldn't buy."))
                return
            end
            self:save()
            self:refresh()
        end,
    })
end

function MerchantScreen:onSell()
    local g = self.game
    local rows = {}
    for i, good in ipairs(g:getGoods()) do
        if (g.inventory[i] or 0) > 0 then
            local idx = i
            local price = g:hasPrice(i) and g:money(g.prices[i]) or _("(no buyers)")
            rows[#rows + 1] = { {
                text = T(_("%1 ×%2 — %3"), good.name, g.inventory[i], price),
                callback = function()
                    UIManager:close(self._dialog)
                    self:promptSell(idx)
                end,
            } }
        end
    end
    if #rows == 0 then
        self:info(_("You have nothing to sell."))
        return
    end
    rows[#rows + 1] = { { text = _("Cancel"), callback = function() UIManager:close(self._dialog) end } }
    self._dialog = ButtonDialog:new{ title = _("Sell what?"), title_align = "center", buttons = rows }
    UIManager:show(self._dialog)
end

function MerchantScreen:promptSell(i)
    local g = self.game
    local good = g:getGoods()[i]
    if not g:hasPrice(i) then
        self:info(_("Nobody here is buying that."))
        return
    end
    local max = g.inventory[i]
    UIManager:show(SpinWidget:new{
        title_text = T(_("Sell %1"), good.name),
        info_text = T(_("%1 each · you hold %2"), g:money(g.prices[i]), max),
        value = max,
        value_min = 1,
        ok_always_enabled = true,
        value_max = max,
        value_step = 1,
        value_hold_step = 10,
        ok_text = _("Sell"),
        callback = function(spin)
            local ok, err = g:sell(i, spin.value)
            if not ok then
                self:info(err or _("Couldn't sell."))
                return
            end
            self:save()
            self:refresh()
        end,
    })
end

-- ------------------------------------------------------------------ travel --

function MerchantScreen:onTravel()
    local g = self.game
    local rows = {}
    for _, loc in ipairs(g:getLocations()) do
        if loc ~= g.location then
            local dest = loc
            rows[#rows + 1] = { {
                text = dest,
                callback = function()
                    UIManager:close(self._dialog)
                    self:travelTo(dest)
                end,
            } }
        end
    end
    rows[#rows + 1] = { { text = _("Stay"), callback = function() UIManager:close(self._dialog) end } }
    self._dialog = ButtonDialog:new{ title = g.theme.travel_prompt, title_align = "center", buttons = rows }
    UIManager:show(self._dialog)
end

function MerchantScreen:travelTo(dest)
    local messages = self.game:travel(dest)
    self:save()
    self:refresh()
    if #messages > 0 then
        self:info(table.concat(messages, "\n"))
    end
    self:handlePending()
    if self.game.game_over then
        self:showGameOver()
    end
end

-- Resolve any interactive event the last turn produced (an enemy encounter or
-- an offer for a weapon / more capacity). Shown on top of any travel popup.
function MerchantScreen:handlePending()
    local g = self.game
    local p = g.pending
    if not p then
        return
    end
    if p.type == "enemy" then
        self:showEnemy()
    elseif p.type == "weapon" then
        self:showOffer(T(g.theme.weapon_offer, g:money(p.price)))
    elseif p.type == "capacity" then
        self:showOffer(T(g.theme.capacity_offer, p.slots, g:money(p.price)))
    end
end

function MerchantScreen:showOffer(prompt)
    local dialog
    dialog = ButtonDialog:new{
        title = prompt,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Buy"),
                    callback = function()
                        UIManager:close(dialog)
                        local _, msg = self.game:acceptOffer()
                        self:save()
                        self:refresh()
                        if msg then self:info(msg) end
                    end,
                },
                {
                    text = _("No thanks"),
                    callback = function()
                        UIManager:close(dialog)
                        self.game:declineOffer()
                        self:save()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function MerchantScreen:showEnemy()
    local g = self.game
    local p = g.pending
    if not p then return end
    local dialog
    dialog = ButtonDialog:new{
        title = T(g.theme.enemy_title, p.count, g.health, g.weapons),
        title_align = "center",
        buttons = {
            {
                {
                    text = g.theme.fight_label,
                    enabled = g.weapons > 0,
                    callback = function()
                        UIManager:close(dialog)
                        self:resolveCombat(g:fight())
                    end,
                },
                {
                    text = g.theme.flee_label,
                    callback = function()
                        UIManager:close(dialog)
                        self:resolveCombat(g:flee())
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function MerchantScreen:resolveCombat(res)
    self:save()
    self:refresh()
    if res.messages and #res.messages > 0 then
        self:info(table.concat(res.messages, "\n"))
    end
    if res.dead then
        self:showGameOver(true)
    elseif not res.ended then
        -- the encounter continues
        self:showEnemy()
    end
end

-- ----------------------------------------------------------- loan & bank ---

function MerchantScreen:onLender()
    local g = self.game
    local dialog
    dialog = ButtonDialog:new{
        title = T(g.theme.lender_title, g:money(g.debt)),
        title_align = "center",
        buttons = {
            { {
                text = _("Pay back"),
                enabled = g.debt > 0 and g.cash > 0,
                callback = function()
                    UIManager:close(dialog)
                    self:promptAmount(_("Pay back"), math.min(g.cash, g.debt), function(v)
                        g:payDebt(v)
                    end)
                end,
            } },
            { {
                text = _("Borrow"),
                callback = function()
                    UIManager:close(dialog)
                    self:promptAmount(_("Borrow"), math.max(1000, g.cash * 2 + 1000), function(v)
                        g:borrow(v)
                    end)
                end,
            } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function MerchantScreen:onBank()
    local g = self.game
    local dialog
    dialog = ButtonDialog:new{
        title = T(g.theme.bank_title, g:money(g.bank)),
        title_align = "center",
        buttons = {
            { {
                text = _("Deposit"),
                enabled = g.cash > 0,
                callback = function()
                    UIManager:close(dialog)
                    self:promptAmount(_("Deposit"), g.cash, function(v)
                        g:deposit(v)
                    end)
                end,
            } },
            { {
                text = _("Withdraw"),
                enabled = g.bank > 0,
                callback = function()
                    UIManager:close(dialog)
                    self:promptAmount(_("Withdraw"), g.bank, function(v)
                        g:withdraw(v)
                    end)
                end,
            } },
            { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function MerchantScreen:promptAmount(title, max, apply)
    max = math.floor(max)
    if max < 1 then
        self:info(_("Nothing to do here right now."))
        return
    end
    UIManager:show(SpinWidget:new{
        title_text = title,
        info_text = T(_("Up to %1"), self.game:money(max)),
        value = max,
        value_min = 1,
        ok_always_enabled = true,
        value_max = max,
        value_step = 1,
        value_hold_step = math.max(1, math.floor(max / 10)),
        ok_text = title,
        callback = function(spin)
            apply(spin.value)
            self:save()
            self:refresh()
        end,
    })
end

-- ----------------------------------------------------------- game lifecycle --

function MerchantScreen:newGame()
    self.game:newGame(self.plugin:getTheme())
    self:save()
    self:refresh()
end

function MerchantScreen:showGameOver(dead)
    local g = self.game
    local net = g:netWorth()
    local high = self.plugin:recordScore(net)
    local headline = dead and g.theme.busted_msg or _("30 days are up.")
    local body = T(_("%1\n\nFinal net worth: %2\nBest ever: %3"),
        headline, g:money(net), g:money(high))
    local dialog
    dialog = ButtonDialog:new{
        title = body,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("New game"),
                    callback = function()
                        UIManager:close(dialog)
                        self:newGame()
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(dialog)
                        self:onCloseButton()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function MerchantScreen:onNewGame()
    local dialog
    dialog = ButtonDialog:new{
        title = _("Start a new game? Current progress is lost."),
        title_align = "center",
        buttons = {
            {
                {
                    text = _("New game"),
                    callback = function()
                        UIManager:close(dialog)
                        self:newGame()
                    end,
                },
                { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            },
        },
    }
    UIManager:show(dialog)
end

function MerchantScreen:onCloseButton()
    self:save()
    self.plugin:onScreenClosed()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

function MerchantScreen:onClose()
    self:onCloseButton()
    return true
end

-- ================================================================= plugin ===

local Merchant = WidgetContainer:extend{
    name = "merchant",
    is_doc_only = false,
}

function Merchant:ensureSettings()
    if not self.settings then
        self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/merchant.lua")
    end
end

-- Make "open the game" available in Dispatcher so the user can bind it to a
-- gesture or profile (Gesture manager → General → Open merchant game).
function Merchant:onDispatcherRegisterActions()
    Dispatcher:registerAction("merchant_open_game",
        {category="none", event="MerchantOpenGame", title=_("Open merchant game"), general=true})
end

function Merchant:init()
    self:ensureSettings()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Merchant:onMerchantOpenGame()
    self:showGame()
    return true
end

function Merchant:getTheme()
    self:ensureSettings()
    return Themes.get(self.settings:readSetting("theme"))
end

function Merchant:addToMainMenu(menu_items)
    local theme_items = {}
    for i = 1, #Themes.list do
        -- no `for _, theme in ipairs(...)` here: that would shadow the
        -- gettext alias `_` used inside the callback below
        local theme = Themes.list[i]
        local id = theme.id
        table.insert(theme_items, {
            text = theme.name,
            radio = true,
            checked_func = function()
                return self:getTheme().id == id
            end,
            callback = function()
                self.settings:saveSetting("theme", id)
                self.settings:flush()
                if self.game and self.game.theme.id ~= id then
                    UIManager:show(InfoMessage:new{
                        text = _("The new theme starts with your next new game; the current run keeps its theme."),
                    })
                end
            end,
        })
    end
    menu_items.merchant = {
        text = _("Merchant"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Play"),
                callback = function()
                    self:showGame()
                end,
            },
            {
                text_func = function()
                    return T(_("Theme: %1"), self:getTheme().name)
                end,
                sub_item_table = theme_items,
            },
        },
    }
end

function Merchant:getGame()
    if not self.game then
        self:ensureSettings()
        self.game = MerchantGame:new(self:getTheme())
        local state = self.settings:readSetting("state")
        if state and not self.game.game_over then
            self.game:load(state)
        end
    end
    return self.game
end

function Merchant:saveState()
    if not self.game then
        return
    end
    self:ensureSettings()
    self.settings:saveSetting("state", self.game:serialize())
    self.settings:flush()
end

-- High scores are kept per theme, since prices are the same but the flavour
-- (and the fun of beating your own record) belongs to each setting.
function Merchant:recordScore(net)
    self:ensureSettings()
    local id = self.game and self.game.theme.id or Themes.default_id
    local scores = self.settings:readSetting("high_scores") or {}
    local high = scores[id] or 0
    if net > high then
        high = net
        scores[id] = high
        self.settings:saveSetting("high_scores", scores)
        self.settings:flush()
    end
    return high
end

function Merchant:showGame()
    if self.screen then
        return
    end
    self.screen = MerchantScreen:new{
        game = self:getGame(),
        plugin = self,
    }
    UIManager:show(self.screen)
end

function Merchant:onScreenClosed()
    self.screen = nil
end

return Merchant
