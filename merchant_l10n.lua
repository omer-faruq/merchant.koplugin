-- merchant_l10n.lua — plugin-local translations.
--
-- KOReader's central gettext only translates strings that live in the
-- KOReader repository (l10n/<lang>/koreader.po), so an out-of-tree plugin has
-- to carry its own dictionaries: merchant_l10n/<lang>.lua, one file per
-- language, mapping the English source string to its translation.
--
-- Lookup order for _("..."):
--   1. plugin dictionary for the UI language (exact code, then its prefix:
--      "pt_BR" -> merchant_l10n/pt_BR.lua -> merchant_l10n/pt.lua)
--   2. KOReader's core gettext (covers common words in every language)
--   3. the English source string itself
--
-- Safe to require outside KOReader (plain LuaJIT tests): without
-- G_reader_settings/gettext it degrades to the identity function.
-- If this plugin is ever merged into KOReader proper, delete this layer and
-- switch the `require("merchant_l10n")` lines back to `require("gettext")`.
local M = { dict = nil }

local core_gettext
do
    local ok, gt = pcall(require, "gettext")
    if ok and gt then core_gettext = gt end
end

local function uiLanguage()
    if type(G_reader_settings) ~= "table" and type(G_reader_settings) ~= "userdata" then return nil end
    local ok, lang = pcall(function() return G_reader_settings:readSetting("language") end)
    if ok and type(lang) == "string" and lang ~= "" then return lang end
    return nil
end

local function loadDict()
    local lang = uiLanguage()
    if not lang or lang:sub(1, 2) == "en" then return {} end
    local prefix = lang:match("^([^_%-]+)")
    for _, cand in ipairs({ lang, prefix }) do
        if cand and cand ~= "" then
            local ok, t = pcall(require, "merchant_l10n/" .. cand)
            if ok and type(t) == "table" then return t end
        end
    end
    return {}
end

-- Drop the cached dictionary (e.g. in tests after switching language).
function M.reload()
    M.dict = nil
end

setmetatable(M, { __call = function(self, msgid)
    if not self.dict then self.dict = loadDict() end
    local s = self.dict[msgid]
    if s ~= nil then return s end
    if core_gettext then
        local ok, t = pcall(core_gettext, msgid)
        if ok and type(t) == "string" and t ~= msgid then return t end
    end
    return msgid
end })

return M
