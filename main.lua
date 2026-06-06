--[[--
Book Nook Charms plugin for KOReader.

Allows users to swap and resize their digital bookmark (dogear) icon
directly from the Tools menu, without needing a computer.

Custom dogear designs can be placed in either:
    <plugin_folder>/icons/         (legacy bundled icons)
    <koreader_data_dir>/icons/booknookcharms/  (user-added icons)

@module koplugin.BookNookCharms
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen

local function screenScaleBySize(size)
    if Screen and Screen.scaleBySize then
        return Screen:scaleBySize(size)
    end
    return size
end

local function safeRegisterAction(name, spec)
    if not Dispatcher or not Dispatcher.registerAction then
        logger.warn("BookNookCharms: gesture action registration is unavailable on this KOReader build")
        return false
    end
    local ok, err = pcall(function()
        Dispatcher:registerAction(name, spec)
    end)
    if not ok then
        logger.warn("BookNookCharms: could not register action", name, err)
    end
    return ok
end

local function safeRegisterMainMenu(plugin)
    if not plugin.ui or not plugin.ui.menu or not plugin.ui.menu.registerToMainMenu then
        logger.warn("BookNookCharms: main menu registration is unavailable on this KOReader build")
        return false
    end
    local ok, err = pcall(function()
        plugin.ui.menu:registerToMainMenu(plugin)
    end)
    if not ok then
        logger.warn("BookNookCharms: could not register main menu", err)
    end
    return ok
end

-- Settings key constants
local S_CUSTOM_ICON      = "bookmarkchrome_custom_icon"
local S_CUSTOM_ICON_NAME = "bookmarkchrome_custom_icon_name"
local S_SCALE_FACTOR     = "bookmarkchrome_scale_factor"
local S_MARGIN_TOP       = "bookmarkchrome_margin_top"
local S_MARGIN_RIGHT     = "bookmarkchrome_margin_right"
local S_RECENT_DESIGNS   = "bookmarkchrome_recent_designs"
local S_FAVORITE_DESIGNS = "booknookcharms_favorite_designs"
local S_FAVORITE_INDEX   = "booknookcharms_favorite_index"
local S_DEFAULT_ICON     = "booknookcharms_default_icon"
local S_DEFAULT_ICON_NAME = "booknookcharms_default_icon_name"
local S_DEFAULT_SCALE    = "booknookcharms_default_scale"
local S_DEFAULT_MARGIN_TOP = "booknookcharms_default_margin_top"
local S_DEFAULT_MARGIN_RIGHT = "booknookcharms_default_margin_right"
local S_DAY_PAIR_ICON  = "booknookcharms_day_pair_icon"
local S_DAY_PAIR_NAME  = "booknookcharms_day_pair_name"
local S_DAY_PAIR_SCALE = "booknookcharms_day_pair_scale"
local S_DAY_PAIR_TOP   = "booknookcharms_day_pair_top"
local S_DAY_PAIR_RIGHT = "booknookcharms_day_pair_right"
local S_NIGHT_PAIR_ICON  = "booknookcharms_night_pair_icon"
local S_NIGHT_PAIR_NAME  = "booknookcharms_night_pair_name"
local S_NIGHT_PAIR_SCALE = "booknookcharms_night_pair_scale"
local S_NIGHT_PAIR_TOP   = "booknookcharms_night_pair_top"
local S_NIGHT_PAIR_RIGHT = "booknookcharms_night_pair_right"
local S_AUTO_PAIR_SWITCH = "booknookcharms_auto_pair_switch"
local S_LAST_PAIR_MODE   = "booknookcharms_last_pair_mode"
local S_FIRST_RUN_DEFAULT = "booknookcharms_first_run_default_applied"
local B_CUSTOM_ICON      = "bookmarkchrome_book_icon"
local B_CUSTOM_ICON_NAME = "bookmarkchrome_book_icon_name"
local B_SCALE_FACTOR     = "bookmarkchrome_book_scale"
local B_MARGIN_TOP       = "bookmarkchrome_book_margin_top"
local B_MARGIN_RIGHT     = "bookmarkchrome_book_margin_right"
-- Margin scaling: top and right increments use the same base step size
local MAX_STEPS = 20
local MIN_SCALE = 0.5
local MAX_SCALE = 6.0

local BookmarkChrome = WidgetContainer:extend{
    name = "booknookcharms",
    is_doc_only = false,
}

-- Supported image extensions for dogear designs.
local SUPPORTED_EXTENSIONS = {
    [".png"] = true,
    [".svg"] = true,
    [".alpha"] = true,
    [".bmp"] = true,
    [".jpg"] = true,
    [".jpeg"] = true,
}

local DEFAULT_NEW_SELECTION_SCALE = 4.0
local DEFAULT_RIBBON_RIGHT_STEPS = 5
local DEFAULT_RIBBON_SELECTION_SCALE = 2.5
local FIRST_RUN_DEFAULT_CHARM = "dogear_soft_original.svg"
local PLUGIN_VERSION = "1.1.0"
local PLUGIN_AUTHOR = "KitanaCode"

local function isRibbonDesign(filename)
    return filename and filename:lower():match("^ribbon_") ~= nil
end

local function isEInkDesign(filename)
    return filename and filename:lower():match("_eink_") ~= nil
end

local function normalizeDesignName(filename)
    if not filename then return nil end
    local name = tostring(filename):match("([^/]+)$") or tostring(filename)
    name = name:gsub("^ribbon_night_public_", "ribbon_night_")
    name = name:gsub("^dogear_night_public_", "dogear_night_")
    name = name:gsub("^ribbon_public_", "ribbon_")
    name = name:gsub("^dogear_public_", "dogear_")
    return name
end


local FAVORITE_LOOKS = {
    { label = "Soft Original Dog-ear", file = "dogear_soft_original.svg" },
    { label = "Soft Rose Dog-ear",     file = "dogear_soft_rose.svg" },
    { label = "Soft Sage Dog-ear",     file = "dogear_soft_sage.svg" },
    { label = "Classic Red Ribbon",    file = "ribbon_classic_red.svg" },
    { label = "Gold Ribbon",           file = "ribbon_gold.svg" },
    { label = "Plum Ribbon",           file = "ribbon_plum.svg" },
    { label = "Moonlit Dog-ear",       file = "dogear_night_moonlit.svg" },
    { label = "Plum Dog-ear",          file = "dogear_night_plum.svg" },
    { label = "Night Red Ribbon",      file = "ribbon_night_red.svg" },
    { label = "Teal Night Ribbon",     file = "ribbon_night_teal.svg" },
    { label = "Violet Night Ribbon",   file = "ribbon_night_violet.svg" },
    { label = "Copper Night Ribbon",   file = "ribbon_night_copper.svg" },
}

local NIGHT_LOOKS = {
    { label = "Moonlit Dog-ear",         file = "dogear_night_moonlit.svg" },
    { label = "Ash Dog-ear",             file = "dogear_night_ash.svg" },
    { label = "Plum Dog-ear",            file = "dogear_night_plum.svg" },
    { label = "Burgundy Dog-ear",        file = "dogear_night_burgundy.svg" },
    { label = "Deep Teal Dog-ear",       file = "dogear_night_deep_teal.svg" },
    { label = "Slate Blue Dog-ear",      file = "dogear_night_slate_blue.svg" },
    { label = "Midnight Ribbon",         file = "ribbon_night_midnight.svg" },
    { label = "Plum Ribbon",             file = "ribbon_night_plum.svg" },
    { label = "Night Red Ribbon",        file = "ribbon_night_red.svg" },
    { label = "Teal Ribbon",             file = "ribbon_night_teal.svg" },
    { label = "Burgundy Ribbon",         file = "ribbon_night_burgundy.svg" },
    { label = "Deep Blue Ribbon",        file = "ribbon_night_deep_blue.svg" },
    { label = "Emerald Ribbon",          file = "ribbon_night_emerald.svg" },
    { label = "Violet Ribbon",           file = "ribbon_night_violet.svg" },
    { label = "Copper Ribbon",           file = "ribbon_night_copper.svg" },
    { label = "Frost E-ink Dog-ear",     file = "dogear_night_eink_frost.svg" },
    { label = "Pearl E-ink Dog-ear",     file = "dogear_night_eink_pearl.svg" },
    { label = "Smoke E-ink Dog-ear",     file = "dogear_night_eink_smoke.svg" },
    { label = "Dither E-ink Dog-ear",    file = "dogear_night_eink_dither.svg" },
    { label = "Oil Slick E-ink Dog-ear", file = "dogear_night_eink_oil_slick.svg" },
    { label = "Obsidian E-ink Dog-ear",  file = "dogear_night_eink_obsidian.svg" },
    { label = "Frost E-ink Ribbon",      file = "ribbon_night_eink_frost.svg" },
    { label = "Pearl E-ink Ribbon",      file = "ribbon_night_eink_pearl.svg" },
    { label = "Smoke E-ink Ribbon",      file = "ribbon_night_eink_smoke.svg" },
    { label = "Dither E-ink Ribbon",     file = "ribbon_night_eink_dither.svg" },
    { label = "Oil Slick E-ink Ribbon",  file = "ribbon_night_eink_oil_slick.svg" },
    { label = "Obsidian E-ink Ribbon",   file = "ribbon_night_eink_obsidian.svg" },
}

local EINK_LOOKS = {
    { label = "E-ink Frost", file = "dogear_eink_frost.svg" },
    { label = "E-ink Frost", file = "ribbon_eink_frost.svg" },
    { label = "E-ink Pearl", file = "dogear_eink_pearl.svg" },
    { label = "E-ink Pearl", file = "ribbon_eink_pearl.svg" },
    { label = "E-ink Smoke", file = "dogear_eink_smoke.svg" },
    { label = "E-ink Smoke", file = "ribbon_eink_smoke.svg" },
    { label = "E-ink Dither", file = "dogear_eink_dither.svg" },
    { label = "E-ink Dither", file = "ribbon_eink_dither.svg" },
    { label = "E-ink Oil Slick", file = "dogear_eink_oil_slick.svg" },
    { label = "E-ink Oil Slick", file = "ribbon_eink_oil_slick.svg" },
    { label = "E-ink Obsidian", file = "dogear_eink_obsidian.svg" },
    { label = "E-ink Obsidian", file = "ribbon_eink_obsidian.svg" },
    { label = "E-ink Frost Night", file = "dogear_night_eink_frost.svg" },
    { label = "E-ink Frost Night", file = "ribbon_night_eink_frost.svg" },
    { label = "E-ink Pearl Night", file = "dogear_night_eink_pearl.svg" },
    { label = "E-ink Pearl Night", file = "ribbon_night_eink_pearl.svg" },
    { label = "E-ink Smoke Night", file = "dogear_night_eink_smoke.svg" },
    { label = "E-ink Smoke Night", file = "ribbon_night_eink_smoke.svg" },
    { label = "E-ink Dither Night", file = "dogear_night_eink_dither.svg" },
    { label = "E-ink Dither Night", file = "ribbon_night_eink_dither.svg" },
    { label = "E-ink Oil Slick Night", file = "dogear_night_eink_oil_slick.svg" },
    { label = "E-ink Oil Slick Night", file = "ribbon_night_eink_oil_slick.svg" },
    { label = "E-ink Obsidian Night", file = "dogear_night_eink_obsidian.svg" },
    { label = "E-ink Obsidian Night", file = "ribbon_night_eink_obsidian.svg" },
}
local function displayCharmName(filename)
    local raw = tostring(filename or "")
    local is_night = raw:lower():match("_night_") ~= nil or raw:lower():match("^night_") ~= nil

    local label = raw
    label = label:gsub("%.svg$", "")
    label = label:gsub("%.png$", "")
    label = label:gsub("%.jpg$", "")
    label = label:gsub("%.jpeg$", "")
    label = label:gsub("%.bmp$", "")
    label = label:gsub("%.alpha$", "")

    label = label:gsub("^ribbon_", "")
    label = label:gsub("^dogear_", "")
    label = label:gsub("^night_", "")
    label = label:gsub("_night_", "_")
    label = label:gsub("_", " ")

    -- Capitalize each word.
    label = label:gsub("(%S+)", function(word)
        return word:gsub("^%l", string.upper)
    end)

    if is_night and not label:lower():match(" night$") then
        label = label .. " Night"
    end

    return label
end

local function niceLabel(filename)
    return displayCharmName(filename)
end

local function charmPreviewPrefix(filename)
    local lower = tostring(filename or ""):lower()
    local shape = isRibbonDesign(lower) and "▌" or "◢"
    if isEInkDesign(lower) then
        if lower:match("frost") or lower:match("pearl") then
            shape = shape .. "○"
        elseif lower:match("smoke") or lower:match("dither") then
            shape = shape .. "◐"
        else
            shape = shape .. "●"
        end
    end
    if lower:match("_night_") then
        return "☾ " .. shape .. " "
    end
    return shape .. " "
end

--- Compute pixel step size for margins based on current screen.
-- Both top and right use the same step so one increment moves equally.
-- @return step_px, step_px
local function getMarginStepSizes()
    local screen_min = math.min(Screen:getWidth(), Screen:getHeight())
    local base = math.max(2, math.ceil(screen_min / 128))
    return base, base
end

--- Convert step count to pixels for top margin.
local function topStepsToPx(steps)
    local top_step = getMarginStepSizes()
    return steps * top_step
end

--- Convert step count to pixels for right margin.
local function rightStepsToPx(steps)
    local _, right_step = getMarginStepSizes()
    return steps * right_step
end

function BookmarkChrome:getDataDogearsDir()
    return DataStorage:getDataDir() .. "/icons/booknookcharms/dogears"
end

function BookmarkChrome:getDataCustomIconsDir()
    return DataStorage:getDataDir() .. "/icons/booknookcharms/custom_icons"
end

function BookmarkChrome:getLegacyIconsDir()
    return DataStorage:getDataDir() .. "/icons/bookmarkchrome"
end

function BookmarkChrome:getLegacyDataDogearsDir()
    return DataStorage:getDataDir() .. "/icons/bookmarkchrome/dogears"
end

function BookmarkChrome:getLegacyDataCustomIconsDir()
    return DataStorage:getDataDir() .. "/icons/bookmarkchrome/custom_icons"
end

function BookmarkChrome:getPluginDogearsDir()
    return self.path .. "/dogears"
end

function BookmarkChrome:getPluginCustomIconsDir()
    return self.path .. "/custom_icons"
end

function BookmarkChrome:getPluginLegacyIconsDir()
    return self.path .. "/icons"
end

function BookmarkChrome:getIconsDir()
    return self:getDataCustomIconsDir()
end

function BookmarkChrome:getPluginIconsDir()
    return self:getPluginDogearsDir()
end

function BookmarkChrome:getPluginRibbonsDir()
    return self.path .. "/ribbons"
end

function BookmarkChrome:getPluginNightDir()
    return self.path .. "/night"
end

function BookmarkChrome:getPluginEInkDir()
    return self.path .. "/eink"
end

function BookmarkChrome:getDataRibbonsDir()
    return DataStorage:getDataDir() .. "/icons/booknookcharms/ribbons"
end

function BookmarkChrome:getDataNightDir()
    return DataStorage:getDataDir() .. "/icons/booknookcharms/night"
end

function BookmarkChrome:getDataEInkDir()
    return DataStorage:getDataDir() .. "/icons/booknookcharms/eink"
end

function BookmarkChrome:getLegacyDataRibbonsDir()
    return DataStorage:getDataDir() .. "/icons/bookmarkchrome/ribbons"
end

function BookmarkChrome:getLegacyDataNightDir()
    return DataStorage:getDataDir() .. "/icons/bookmarkchrome/night"
end

function BookmarkChrome:getLegacyDataEInkDir()
    return DataStorage:getDataDir() .. "/icons/bookmarkchrome/eink"
end

local function scanDir(dir, list, seen)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local ext = entry:match("(%.[^%.]+)$")
            if ext and SUPPORTED_EXTENSIONS[ext:lower()] and not seen[entry] then
                seen[entry] = true
                table.insert(list, { text = entry, path = dir .. "/" .. entry })
            end
        end
    end
end

function BookmarkChrome:scanDesigns()
    local designs = {}
    local seen = {}
    -- Bundled dog-ears live in dogears/.
    -- Bundled ribbons live in ribbons/.
    -- Bundled night charms live in night/.
    -- Bundled e-ink charms live in eink/.
    -- Users can add their own files in custom_icons/.
    -- Legacy icons/ folders are still scanned for backward compatibility.
    -- Any filename beginning with ribbon_ is treated as a ribbon no matter where it is found.
    scanDir(self:getPluginEInkDir(), designs, seen)
    scanDir(self:getPluginDogearsDir(), designs, seen)
    scanDir(self:getPluginRibbonsDir(), designs, seen)
    scanDir(self:getPluginNightDir(), designs, seen)
    scanDir(self:getDataEInkDir(), designs, seen)
    scanDir(self:getPluginCustomIconsDir(), designs, seen)
    scanDir(self:getDataDogearsDir(), designs, seen)
    scanDir(self:getDataRibbonsDir(), designs, seen)
    scanDir(self:getDataNightDir(), designs, seen)
    scanDir(self:getDataCustomIconsDir(), designs, seen)
    scanDir(self:getLegacyDataEInkDir(), designs, seen)
    scanDir(self:getLegacyDataDogearsDir(), designs, seen)
    scanDir(self:getLegacyDataRibbonsDir(), designs, seen)
    scanDir(self:getLegacyDataNightDir(), designs, seen)
    scanDir(self:getLegacyDataCustomIconsDir(), designs, seen)
    scanDir(self:getPluginLegacyIconsDir(), designs, seen)
    scanDir(self:getLegacyIconsDir(), designs, seen)
    table.sort(designs, function(a, b)
        local ar, br = isRibbonDesign(a.text), isRibbonDesign(b.text)
        if ar ~= br then return not ar end
        return a.text < b.text
    end)
    return designs
end

function BookmarkChrome:applyDogearToLive(skip_feedback)
    local dogear_widget = self.ui and self.ui.view and self.ui.view.dogear

    if dogear_widget then
        dogear_widget.dogear_size = nil
        dogear_widget:setupDogear()
        dogear_widget:resetLayout()
        UIManager:setDirty(dogear_widget, "ui")

        -- Safe bookmark feedback animation.
        -- Skipped during Charm Studio live preview to reduce visible flashing.
        if not skip_feedback then
            UIManager:scheduleIn(0.05, function()
                if dogear_widget then
                    UIManager:setDirty(dogear_widget, "partial")
                end
            end)
            UIManager:scheduleIn(0.12, function()
                if dogear_widget then
                    UIManager:setDirty(dogear_widget, "ui")
                end
            end)
        end
    end
end

--- Reset all dogear settings to defaults.
function BookmarkChrome:resetAll()
    local default_icon = G_reader_settings:readSetting(S_DEFAULT_ICON)
    local default_name = G_reader_settings:readSetting(S_DEFAULT_ICON_NAME)
    local resolved_name, resolved_path = self:resolveSavedDesign(default_icon, default_name)

    if resolved_path and resolved_name then
        G_reader_settings:saveSetting(S_DEFAULT_ICON, resolved_path)
        G_reader_settings:saveSetting(S_DEFAULT_ICON_NAME, resolved_name)
        G_reader_settings:saveSetting(S_CUSTOM_ICON, resolved_path)
        G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, resolved_name)
        G_reader_settings:saveSetting(S_SCALE_FACTOR, G_reader_settings:readSetting(S_DEFAULT_SCALE) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_SELECTION_SCALE or DEFAULT_NEW_SELECTION_SCALE))
        G_reader_settings:saveSetting(S_MARGIN_TOP, G_reader_settings:readSetting(S_DEFAULT_MARGIN_TOP) or 0)
        G_reader_settings:saveSetting(S_MARGIN_RIGHT, G_reader_settings:readSetting(S_DEFAULT_MARGIN_RIGHT) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_RIGHT_STEPS or 0))
    else
        if default_icon or default_name then
            G_reader_settings:delSetting(S_DEFAULT_ICON)
            G_reader_settings:delSetting(S_DEFAULT_ICON_NAME)
            G_reader_settings:delSetting(S_DEFAULT_SCALE)
            G_reader_settings:delSetting(S_DEFAULT_MARGIN_TOP)
            G_reader_settings:delSetting(S_DEFAULT_MARGIN_RIGHT)
        end
        G_reader_settings:delSetting(S_CUSTOM_ICON)
        G_reader_settings:delSetting(S_CUSTOM_ICON_NAME)
        G_reader_settings:saveSetting(S_SCALE_FACTOR, DEFAULT_NEW_SELECTION_SCALE)
        G_reader_settings:saveSetting(S_MARGIN_TOP, 0)
        G_reader_settings:saveSetting(S_MARGIN_RIGHT, 0)
    end
    self:applyDogearToLive()
end

function BookmarkChrome:findDesignByName(filename, designs)
    designs = designs or self:scanDesigns()
    local target = normalizeDesignName(filename)

    for __, design in ipairs(designs) do
        if design.text == filename or normalizeDesignName(design.text) == target then
            return design
        end
    end
end

function BookmarkChrome:resolveSavedDesign(saved_path, saved_name, designs)
    if saved_path and lfs.attributes(saved_path, "mode") == "file" then
        return saved_name, saved_path, false
    end

    local design = self:findDesignByName(saved_name or saved_path, designs)
    if design then
        return design.text, design.path, true
    end
end


function BookmarkChrome:pushRecent(filename)
    if not filename then return end
    local recent = G_reader_settings:readSetting(S_RECENT_DESIGNS) or {}
    local out = { filename }
    for __, item in ipairs(recent) do
        if item ~= filename and #out < 8 then
            table.insert(out, item)
        end
    end
    G_reader_settings:saveSetting(S_RECENT_DESIGNS, out)
end

function BookmarkChrome:applyLook(filename, full_path, scale, mt, mr, remember_recent, message)
    if not filename or not full_path then return end
    G_reader_settings:saveSetting(S_CUSTOM_ICON, full_path)
    G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, filename)
    G_reader_settings:saveSetting(S_SCALE_FACTOR, scale or DEFAULT_NEW_SELECTION_SCALE)
    G_reader_settings:saveSetting(S_MARGIN_TOP, mt or 0)
    G_reader_settings:saveSetting(S_MARGIN_RIGHT, mr or (isRibbonDesign(filename) and DEFAULT_RIBBON_RIGHT_STEPS or 0))
    if remember_recent ~= false then
        self:pushRecent(filename)
    end
    self:applyDogearToLive()
    if message then
        UIManager:show(InfoMessage:new{ text = message, timeout = 2 })
    end
end

function BookmarkChrome:saveCurrentCharmPath()
    local name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    local icon = G_reader_settings:readSetting(S_CUSTOM_ICON)
    if not name then return end

    local resolved_name, resolved_path, repaired = self:resolveSavedDesign(icon, name)
    if resolved_name and resolved_path and repaired then
        G_reader_settings:saveSetting(S_CUSTOM_ICON, resolved_path)
        G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, resolved_name)
    end
end

function BookmarkChrome:applyFirstRunDefault()
    if G_reader_settings:readSetting(S_FIRST_RUN_DEFAULT) then return false end
    if G_reader_settings:readSetting(S_CUSTOM_ICON) or G_reader_settings:readSetting(S_CUSTOM_ICON_NAME) then
        G_reader_settings:saveSetting(S_FIRST_RUN_DEFAULT, true)
        return false
    end

    local design = self:findDesignByName(FIRST_RUN_DEFAULT_CHARM)
    if not design then
        G_reader_settings:saveSetting(S_FIRST_RUN_DEFAULT, true)
        return false
    end

    self:applyLook(design.text, design.path, DEFAULT_NEW_SELECTION_SCALE, 0, 0, false)
    G_reader_settings:saveSetting(S_DEFAULT_ICON, design.path)
    G_reader_settings:saveSetting(S_DEFAULT_ICON_NAME, design.text)
    G_reader_settings:saveSetting(S_DEFAULT_SCALE, DEFAULT_NEW_SELECTION_SCALE)
    G_reader_settings:saveSetting(S_DEFAULT_MARGIN_TOP, 0)
    G_reader_settings:saveSetting(S_DEFAULT_MARGIN_RIGHT, 0)
    G_reader_settings:saveSetting(S_FIRST_RUN_DEFAULT, true)
    return true
end

function BookmarkChrome:applyDesign(filename, full_path)
    local is_ribbon = isRibbonDesign(filename)
    local scale = is_ribbon and DEFAULT_RIBBON_SELECTION_SCALE or DEFAULT_NEW_SELECTION_SCALE
    local right = is_ribbon and DEFAULT_RIBBON_RIGHT_STEPS or 0
    local msg = is_ribbon
        and _("Ribbon charm applied at 2.5× with right placement +5.")
        or _("Corner charm applied at 4×.")

    self:applyLook(filename, full_path, scale, 0, right, true, msg)
end

function BookmarkChrome:applyOriginalCorner(message)
    local design = self:findDesignByName(FIRST_RUN_DEFAULT_CHARM)
    if design then
        self:applyLook(design.text, design.path, DEFAULT_NEW_SELECTION_SCALE, 0, 0, false, message)
        return true
    end

    G_reader_settings:delSetting(S_CUSTOM_ICON)
    G_reader_settings:delSetting(S_CUSTOM_ICON_NAME)
    G_reader_settings:saveSetting(S_SCALE_FACTOR, DEFAULT_NEW_SELECTION_SCALE)
    G_reader_settings:saveSetting(S_MARGIN_TOP, 0)
    G_reader_settings:saveSetting(S_MARGIN_RIGHT, 0)
    self:applyDogearToLive()
    if message then
        UIManager:show(InfoMessage:new{ text = message, timeout = 2 })
    end
    return false
end

function BookmarkChrome:saveCurrentLookToBook()
    local ds = self.ui and self.ui.doc_settings
    if not ds then return end
    self:saveCurrentCharmPath()
    ds:saveSetting(B_CUSTOM_ICON, G_reader_settings:readSetting(S_CUSTOM_ICON))
    ds:saveSetting(B_CUSTOM_ICON_NAME, G_reader_settings:readSetting(S_CUSTOM_ICON_NAME))
    ds:saveSetting(B_SCALE_FACTOR, G_reader_settings:readSetting(S_SCALE_FACTOR) or DEFAULT_NEW_SELECTION_SCALE)
    ds:saveSetting(B_MARGIN_TOP, G_reader_settings:readSetting(S_MARGIN_TOP) or 0)
    ds:saveSetting(B_MARGIN_RIGHT, G_reader_settings:readSetting(S_MARGIN_RIGHT) or 0)
    UIManager:show(InfoMessage:new{ text = _("Current charm saved for this book."), timeout = 2 })
end

function BookmarkChrome:applyBookLook(show_message)
    local ds = self.ui and self.ui.doc_settings
    if not ds then return false end
    local icon = ds:readSetting(B_CUSTOM_ICON)
    local name = ds:readSetting(B_CUSTOM_ICON_NAME)
    local resolved_name, resolved_path, repaired = self:resolveSavedDesign(icon, name)
    if resolved_name and resolved_path then
        if repaired then
            ds:saveSetting(B_CUSTOM_ICON, resolved_path)
            ds:saveSetting(B_CUSTOM_ICON_NAME, resolved_name)
        end
        self:applyLook(resolved_name, resolved_path,
            ds:readSetting(B_SCALE_FACTOR) or DEFAULT_NEW_SELECTION_SCALE,
            ds:readSetting(B_MARGIN_TOP) or 0,
            ds:readSetting(B_MARGIN_RIGHT) or 0,
            false,
            show_message and _("Book look restored.") or nil)
        return true
    end
    if icon or name then
        self:resetThisBook(false)
        if show_message then
            UIManager:show(InfoMessage:new{ text = _("This book's saved charm was missing, so it was cleared."), timeout = 2 })
        end
        return false
    end
    if show_message then
        UIManager:show(InfoMessage:new{ text = _("No saved look for this book yet."), timeout = 2 })
    end
    return false
end

function BookmarkChrome:resetThisBook(show_message)
    local ds = self.ui and self.ui.doc_settings
    if not ds then return end
    ds:delSetting(B_CUSTOM_ICON)
    ds:delSetting(B_CUSTOM_ICON_NAME)
    ds:delSetting(B_SCALE_FACTOR)
    ds:delSetting(B_MARGIN_TOP)
    ds:delSetting(B_MARGIN_RIGHT)
    if show_message ~= false then
        UIManager:show(InfoMessage:new{ text = _("This book's saved look was cleared."), timeout = 2 })
    end
end


function BookmarkChrome:setCurrentLookAsDefault()
    local icon = G_reader_settings:readSetting(S_CUSTOM_ICON)
    local name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    local resolved_name, resolved_path = self:resolveSavedDesign(icon, name)

    if not resolved_path or not resolved_name then
        UIManager:show(InfoMessage:new{ text = _("No charm is selected yet."), timeout = 2 })
        return
    end

    G_reader_settings:saveSetting(S_CUSTOM_ICON, resolved_path)
    G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, resolved_name)
    G_reader_settings:saveSetting(S_DEFAULT_ICON, resolved_path)
    G_reader_settings:saveSetting(S_DEFAULT_ICON_NAME, resolved_name)
    G_reader_settings:saveSetting(S_DEFAULT_SCALE, G_reader_settings:readSetting(S_SCALE_FACTOR) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_SELECTION_SCALE or DEFAULT_NEW_SELECTION_SCALE))
    G_reader_settings:saveSetting(S_DEFAULT_MARGIN_TOP, G_reader_settings:readSetting(S_MARGIN_TOP) or 0)
    G_reader_settings:saveSetting(S_DEFAULT_MARGIN_RIGHT, G_reader_settings:readSetting(S_MARGIN_RIGHT) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_RIGHT_STEPS or 0))

    UIManager:show(InfoMessage:new{ text = _("Default charm saved ✧"), timeout = 2 })
end


function BookmarkChrome:getFavoriteDesigns()
    return G_reader_settings:readSetting(S_FAVORITE_DESIGNS) or {}
end

function BookmarkChrome:addCurrentToFavorites()
    local name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)

    if not name then
        UIManager:show(InfoMessage:new{ text = _("No charm is selected yet."), timeout = 2 })
        return
    end

    name = normalizeDesignName(name)
    local favorites = G_reader_settings:readSetting(S_FAVORITE_DESIGNS) or {}
    local target = normalizeDesignName(name)

    for __, item in ipairs(favorites) do
        if normalizeDesignName(item) == target then
            UIManager:show(InfoMessage:new{ text = _("Already in Favorite Charms ⭐"), timeout = 2 })
            self:refreshFavoriteCharmItems()
            return
        end
    end

    table.insert(favorites, 1, name)
    while #favorites > 20 do
        table.remove(favorites)
    end

    G_reader_settings:saveSetting(S_FAVORITE_DESIGNS, favorites)
    self:refreshFavoriteCharmItems()
    UIManager:show(InfoMessage:new{ text = _("Added to Favorite Charms ⭐"), timeout = 2 })
end


function BookmarkChrome:removeCurrentFromFavorites()
    local name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)

    if not name then
        UIManager:show(InfoMessage:new{ text = _("No charm is selected yet."), timeout = 2 })
        return
    end

    local target = normalizeDesignName(name)
    local favorites = G_reader_settings:readSetting(S_FAVORITE_DESIGNS) or {}
    local out = {}
    local removed = false

    for __, item in ipairs(favorites) do
        if normalizeDesignName(item) == target then
            removed = true
        else
            table.insert(out, normalizeDesignName(item))
        end
    end

    G_reader_settings:saveSetting(S_FAVORITE_DESIGNS, out)
    self:refreshFavoriteCharmItems()

    if removed then
        UIManager:show(InfoMessage:new{ text = _("Removed from Favorite Charms."), timeout = 2 })
    else
        UIManager:show(InfoMessage:new{ text = _("This charm is not in Favorite Charms."), timeout = 2 })
    end
end


function BookmarkChrome:clearFavorites()
    G_reader_settings:saveSetting(S_FAVORITE_DESIGNS, {})
    G_reader_settings:saveSetting(S_FAVORITE_INDEX, 0)
    self:refreshFavoriteCharmItems()
    UIManager:show(InfoMessage:new{ text = _("Favorite Charms cleared."), timeout = 2 })
end

function BookmarkChrome:applyNextFavoriteCharm()
    local favorites = self:getFavoriteDesigns()
    if #favorites == 0 then
        UIManager:show(InfoMessage:new{ text = _("No favorite charms yet."), timeout = 2 })
        return false
    end

    local designs = self:scanDesigns()
    local start = G_reader_settings:readSetting(S_FAVORITE_INDEX) or 0
    for step = 1, #favorites do
        local index = ((start + step - 1) % #favorites) + 1
        local design = self:findDesignByName(favorites[index], designs)
        if design then
            G_reader_settings:saveSetting(S_FAVORITE_INDEX, index)
            self:applyDesign(design.text, design.path)
            return true
        end
    end

    UIManager:show(InfoMessage:new{ text = _("Favorite charm files are missing."), timeout = 2 })
    return false
end

function BookmarkChrome:pruneMissingFavorites(show_message)
    local designs = self:scanDesigns()
    local favorites = G_reader_settings:readSetting(S_FAVORITE_DESIGNS) or {}
    local out = {}
    local removed = 0

    for __, filename in ipairs(favorites) do
        if self:findDesignByName(filename, designs) then
            table.insert(out, normalizeDesignName(filename))
        else
            removed = removed + 1
        end
    end

    if removed > 0 then
        G_reader_settings:saveSetting(S_FAVORITE_DESIGNS, out)
        self:refreshFavoriteCharmItems()
    end

    if show_message then
        local text = removed > 0
            and _("Missing favorite charms cleaned up.")
            or _("No missing favorite charms found.")
        UIManager:show(InfoMessage:new{ text = text, timeout = 2 })
    end

    return removed
end

function BookmarkChrome:countMissingFavorites(designs)
    designs = designs or self:scanDesigns()
    local missing = 0
    for __, filename in ipairs(G_reader_settings:readSetting(S_FAVORITE_DESIGNS) or {}) do
        if not self:findDesignByName(filename, designs) then
            missing = missing + 1
        end
    end
    return missing
end


function BookmarkChrome:isFavoriteDesign(filename)
    if not filename then return false end
    local target = normalizeDesignName(filename)
    local favorites = G_reader_settings:readSetting(S_FAVORITE_DESIGNS) or {}

    for __, item in ipairs(favorites) do
        if normalizeDesignName(item) == target then return true end
    end

    return false
end


function BookmarkChrome:displayMenuLabel(filename)
    local label = displayCharmName(filename)
    if self:isFavoriteDesign(filename) then
        label = label .. " ⭐"
    end
    return charmPreviewPrefix(filename) .. label
end

function BookmarkChrome:displayEInkMenuLabel(filename, curated_label)
    local label = curated_label or displayCharmName(filename)
    label = label:gsub("^Eink", "E-ink")
    label = label:gsub(" Eink ", " E-ink ")
    if self:isFavoriteDesign(filename) then
        label = label .. " ⭐"
    end
    if isRibbonDesign(filename) then
        return charmPreviewPrefix(filename) .. _("Ribbon") .. " — " .. label
    end
    return charmPreviewPrefix(filename) .. _("Dogear") .. " — " .. label
end

function BookmarkChrome:resetPositionOnly()
    local filename = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    G_reader_settings:saveSetting(S_MARGIN_TOP, 0)
    G_reader_settings:saveSetting(S_MARGIN_RIGHT, isRibbonDesign(filename) and DEFAULT_RIBBON_RIGHT_STEPS or 0)
    self:applyDogearToLive(true)
    UIManager:show(InfoMessage:new{ text = _("Charm position reset."), timeout = 2 })
end

function BookmarkChrome:showFavoriteLooksMenu()
    local designs = self:scanDesigns()
    local favorites = self:getFavoriteDesigns()
    local menu_items = {}

    for __, filename in ipairs(favorites) do
        local design = self:findDesignByName(filename, designs)
        if design then
            table.insert(menu_items, {
                text = self:displayMenuLabel(design.text),
            keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    if #favorites == 0 then
        table.insert(menu_items, {
            text = _("No favorites yet"),
            callback = function()
                UIManager:show(InfoMessage:new{ text = _("Apply a charm first, then add it here."), timeout = 2 })
            end,
        })
    end

    table.insert(menu_items, {
        text = _("Add Current Charm ⭐"),
        callback = function()
            self:addCurrentToFavorites()
        end,
    })

    table.insert(menu_items, {
        text = _("Remove Current Charm"),
        callback = function()
            self:removeCurrentFromFavorites()
        end,
    })

    table.insert(menu_items, {
        text = _("Next Favorite Charm"),
        callback = function()
            self:applyNextFavoriteCharm()
        end,
    })

    table.insert(menu_items, {
        text = _("Clear Favorite Charms"),
        callback = function()
            self:clearFavorites()
        end,
    })

    if self:countMissingFavorites(designs) > 0 then
        table.insert(menu_items, {
            text = _("Remove Missing Favorites"),
            callback = function()
                self:pruneMissingFavorites(true)
            end,
        })
    end

    local fav_menu
    fav_menu = Menu:new{
        title = _("Favorite Charms ⭐"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() UIManager:close(fav_menu) end,
    }
    UIManager:show(fav_menu)
end

function BookmarkChrome:showNightLooksMenu()
    local designs = self:scanDesigns()
    local menu_items = {}
    local added = {}

    for __, look in ipairs(NIGHT_LOOKS) do
        local design = self:findDesignByName(look.file, designs)
        if design and not added[design.text] then
            added[design.text] = true
            table.insert(menu_items, {
                text = self:displayMenuLabel(design.text),
            keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    local custom_night = {}
    local seen = {}
    scanDir(self:getPluginNightDir(), custom_night, seen)
    scanDir(self:getDataNightDir(), custom_night, seen)
    table.sort(custom_night, function(a, b) return a.text < b.text end)

    for __, design in ipairs(custom_night) do
        if not added[design.text] then
            added[design.text] = true
            table.insert(menu_items, {
                text = self:displayMenuLabel(design.text),
            keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    if #menu_items == 0 then
        UIManager:show(InfoMessage:new{ text = _("No night looks found."), timeout = 2 })
        return
    end

    local night_menu
    night_menu = Menu:new{
        title = _("Night Charms ☾"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() UIManager:close(night_menu) end,
    }
    UIManager:show(night_menu)
end

function BookmarkChrome:showRecentlyUsedMenu()
    local recent = G_reader_settings:readSetting(S_RECENT_DESIGNS) or {}
    local designs = self:scanDesigns()
    local menu_items = {}
    for __, filename in ipairs(recent) do
        local design = self:findDesignByName(filename, designs)
        if design then
            table.insert(menu_items, {
                text = self:displayMenuLabel(filename),
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end
    if #menu_items == 0 then
        UIManager:show(InfoMessage:new{ text = _("No recently used bookmarks yet."), timeout = 2 })
        return
    end
    local recent_menu
    recent_menu = Menu:new{
        title = _("Recent Marks"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() UIManager:close(recent_menu) end,
    }
    UIManager:show(recent_menu)
end

function BookmarkChrome:previewCurrentLook()
    self:applyDogearToLive()
    UIManager:show(InfoMessage:new{ text = _("Preview refreshed. Nothing new was saved."), timeout = 2 })
end

function BookmarkChrome:showDesignMenu()
    local designs = self:scanDesigns()

    if #designs == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No custom bookmark designs found.\n\nPlace image files (.png, .svg, .bmp, .jpg) in:\n")
                .. self:getPluginDogearsDir() .. "\n"
                .. self:getPluginCustomIconsDir() .. "\n" .. _("or") .. "\n"
                .. self:getDataCustomIconsDir(),
        })
        return
    end

    local menu_items = {}
    for __, design in ipairs(designs) do
        local filename = design.text
        local full_path = design.path
        table.insert(menu_items, {
            text = self:displayMenuLabel(filename),
            callback = function()
                self:applyDesign(filename, full_path)
            end,
        })
    end

    table.insert(menu_items, {
        text = _("Restore Original Corner"),
        callback = function()
            self:resetAll()
            UIManager:show(InfoMessage:new{ text = _("Default dog-ear restored at 3× with right placement 0."), timeout = 2 })
        end,
    })

    local design_menu
    design_menu = Menu:new{
        title = _("Choose a Charm ✨"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function()
            UIManager:close(design_menu)
        end,
    }

    UIManager:show(design_menu)
end


function BookmarkChrome:showRibbonColorMenu()
    local designs = self:scanDesigns()
    local ribbon_designs = {}
    for __, design in ipairs(designs) do
        if isRibbonDesign(design.text) then
            table.insert(ribbon_designs, design)
        end
    end

    if #ribbon_designs == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No ribbon color designs found.\n\nPlace files named ribbon_*.svg in:\n")
                .. self:getPluginRibbonsDir() .. "\n" .. _("or") .. "\n"
                .. self:getDataRibbonsDir(),
        })
        return
    end

    local menu_items = {}
    for __, design in ipairs(ribbon_designs) do
        table.insert(menu_items, {
            text = self:displayMenuLabel(design.text),
            callback = function()
                self:applyDesign(design.text, design.path)
            end,
        })
    end

    local ribbon_menu
    ribbon_menu = Menu:new{
        title = _("Ribbon Charms ✦"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function()
            UIManager:close(ribbon_menu)
        end,
    }

    UIManager:show(ribbon_menu)
end


function BookmarkChrome:showCornerCharmsMenu()
    local designs = self:scanDesigns()
    local dogear_designs = {}

    for __, design in ipairs(designs) do
        if not isRibbonDesign(design.text) then
            table.insert(dogear_designs, design)
        end
    end

    if #dogear_designs == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No corner charm designs found."),
        })
        return
    end

    local menu_items = {}
    for __, design in ipairs(dogear_designs) do
        table.insert(menu_items, {
            text = self:displayMenuLabel(design.text),
            callback = function()
                self:applyDesign(design.text, design.path)
            end,
        })
    end

    local corner_menu
    corner_menu = Menu:new{
        title = _("Corner Charms 📐"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function()
            UIManager:close(corner_menu)
        end,
    }

    UIManager:show(corner_menu)
end

--- Build a section label widget, left-aligned.
local function sectionLabel(text, inner_w)
    return LeftContainer:new{
        dimen = Geom:new{ w = inner_w, h = screenScaleBySize(28) },
        TextWidget:new{
            text = text,
            face = Font:getFace("smallinfofont", 17),
            bold = true,
        },
    }
end

--- Build a horizontal separator line.
local function separator(inner_w)
    return CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = Size.line.medium },
        LineWidget:new{
            dimen = Geom:new{ w = inner_w, h = Size.line.medium },
            background = Blitbuffer.COLOR_GRAY,
        },
    }
end

--- Build a framed value display box (makes value fields visually distinct).
local function valueBox(text_widget, box_w, box_h)
    local b = Size.border.default
    return FrameContainer:new{
        bordersize = b,
        radius     = Size.radius.button,
        padding    = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = box_w - b * 2, h = box_h - b * 2 },
            text_widget,
        },
    }
end

function BookmarkChrome:showSizeSlider(scale, mt_steps, mr_steps, icon_idx, designs)
    -- Load saved settings if not provided
    if not scale then scale = G_reader_settings:readSetting(S_SCALE_FACTOR) or 1 end
    if not mt_steps then mt_steps = G_reader_settings:readSetting(S_MARGIN_TOP) or 0 end
    if not mr_steps then mr_steps = G_reader_settings:readSetting(S_MARGIN_RIGHT) or 0 end

    -- Round and clamp scale
    scale = math.floor(scale * 10 + 0.5) / 10
    scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))

    -- Clamp margin steps
    mt_steps = math.max(0, math.min(MAX_STEPS, mt_steps))
    mr_steps = math.max(0, math.min(MAX_STEPS, mr_steps))

    -- Save originals on first open so Cancel can revert
    if not self._slider_originals then
        self._slider_originals = {
            scale     = G_reader_settings:readSetting(S_SCALE_FACTOR) or 1,
            mt        = G_reader_settings:readSetting(S_MARGIN_TOP)   or 0,
            mr        = G_reader_settings:readSetting(S_MARGIN_RIGHT) or 0,
            icon      = G_reader_settings:readSetting(S_CUSTOM_ICON),
            icon_name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME),
        }
    end

    -- Scan designs once and pass through rebuilds
    if not designs then
        designs = self:scanDesigns()
    end
    if icon_idx == nil then
        local saved_icon = G_reader_settings:readSetting(S_CUSTOM_ICON)
        local saved_name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
        icon_idx = 0
        if saved_icon or saved_name then
            for i, d in ipairs(designs) do
                if d.path == saved_icon or normalizeDesignName(d.text) == normalizeDesignName(saved_name) then
                    icon_idx = i
                    break
                end
            end
        end
    end
    -- Clamp icon_idx in case designs changed
    icon_idx = math.max(0, math.min(icon_idx, #designs))

    local selected_icon_name = (icon_idx > 0 and designs[icon_idx]) and designs[icon_idx].text or nil

    -- Rebuild: close and reopen with new parameters (passes designs to avoid rescan)
    local top_widget
    local rebuild_pending = false

    -- Apply values to settings and update the live dog ear behind the modal
    local function applyLivePreview(ns, nmt, nmr, ni)
        G_reader_settings:saveSetting(S_SCALE_FACTOR, ns)
        G_reader_settings:saveSetting(S_MARGIN_TOP,   nmt)
        G_reader_settings:saveSetting(S_MARGIN_RIGHT, nmr)
        local ni_path = (ni > 0 and designs[ni]) and designs[ni].path or nil
        local ni_name = (ni > 0 and designs[ni]) and designs[ni].text or nil
        if ni_path then
            G_reader_settings:saveSetting(S_CUSTOM_ICON,      ni_path)
            G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, ni_name)
        else
            G_reader_settings:delSetting(S_CUSTOM_ICON)
            G_reader_settings:delSetting(S_CUSTOM_ICON_NAME)
        end
        self:applyDogearToLive(true)
    end

    local function rebuild(ns, nmt, nmr, ni)
        if rebuild_pending then return end
        rebuild_pending = true
        applyLivePreview(ns, nmt, nmr, ni)
        UIManager:close(top_widget)
        UIManager:scheduleIn(0, function()
            self:showSizeSlider(ns, nmt, nmr, ni, designs)
        end)
    end

    -- Layout dimensions
    local dialog_w  = math.floor(Screen:getWidth() * 0.90)
    local pad       = Size.padding.large
    local inner_w   = dialog_w - pad * 2
    local hspan     = Size.span.horizontal_default
    local vspan_sm  = Size.span.vertical_default
    local vspan_lg  = Size.span.vertical_default * 2
    local btn_h     = screenScaleBySize(52)

    -- === DESIGN section ===
    local icon_btn_w  = math.floor(inner_w * 0.18)
    local icon_name_w = inner_w - icon_btn_w * 2 - hspan * 2
    local icon_display = selected_icon_name and self:displayLibraryTypeLabel(selected_icon_name) or _("Default KOReader corner")

    local icon_row = HorizontalGroup:new{
        align = "center",
        Button:new{
            text = "\u{25C0}",
            width = icon_btn_w,
            enabled = #designs > 0,
            callback = function()
                local new_idx = (icon_idx == 0) and #designs or (icon_idx - 1)
                rebuild(scale, mt_steps, mr_steps, new_idx)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        CenterContainer:new{
            dimen = Geom:new{ w = icon_name_w, h = btn_h },
            TextWidget:new{
                text = icon_display,
                face = Font:getFace("cfont", 18),
                max_width = icon_name_w - Size.padding.default * 2,
            },
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text = "\u{25B6}",
            width = icon_btn_w,
            enabled = #designs > 0,
            callback = function()
                local new_idx = (icon_idx >= #designs) and 0 or (icon_idx + 1)
                rebuild(scale, mt_steps, mr_steps, new_idx)
            end,
        },
    }

    -- === SIZE section ===
    local step_btn_w  = math.floor((inner_w - (hspan * 4)) * 0.18)
    local value_box_w = inner_w - (step_btn_w * 4) - (hspan * 4)

    local function clampScale(v)
        return math.max(MIN_SCALE, math.min(MAX_SCALE, math.floor(v * 10 + 0.5) / 10))
    end

    local scale_btn_w = math.floor((inner_w - value_box_w - hspan * 2) / 2)
    local scale_row = HorizontalGroup:new{
        align = "center",
        Button:new{ text = _("Smaller"), width = scale_btn_w, callback = function() rebuild(clampScale(scale - 0.1), mt_steps, mr_steps, icon_idx) end },
        HorizontalSpan:new{ width = hspan },
        valueBox(
            TextWidget:new{
                text = string.format("%.1f\u{00D7}", scale),
                face = Font:getFace("cfont", 24),
                bold = true,
            },
            value_box_w, btn_h
        ),
        HorizontalSpan:new{ width = hspan },
        Button:new{ text = _("Bigger"), width = scale_btn_w, callback = function() rebuild(clampScale(scale + 0.1), mt_steps, mr_steps, icon_idx) end },
    }

    -- === POSITION section ===
    local label_w = math.floor(inner_w * 0.20)
    local mbtn_w  = math.floor(inner_w * 0.18)
    local mval_w  = inner_w - label_w - mbtn_w * 2 - hspan * 3

    local function marginRow(label, step_val, on_dec, on_inc)
        return HorizontalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = label_w, h = btn_h },
                TextWidget:new{ text = label, face = Font:getFace("cfont", 18) },
            },
            HorizontalSpan:new{ width = hspan },
            Button:new{ text = "−", width = mbtn_w, callback = on_dec },
            HorizontalSpan:new{ width = hspan },
            valueBox(
                TextWidget:new{
                    text = tostring(step_val),
                    face = Font:getFace("cfont", 20),
                    bold = true,
                },
                mval_w, btn_h
            ),
            HorizontalSpan:new{ width = hspan },
            Button:new{ text = "+", width = mbtn_w, callback = on_inc },
        }
    end

    local top_margin_row = marginRow(
        _("Top"), mt_steps,
        function() rebuild(scale, math.max(0, mt_steps - 1), mr_steps, icon_idx) end,
        function() rebuild(scale, math.min(MAX_STEPS, mt_steps + 1), mr_steps, icon_idx) end
    )
    local right_margin_row = marginRow(
        _("Right"), mr_steps,
        function() rebuild(scale, mt_steps, math.max(0, mr_steps - 1), icon_idx) end,
        function() rebuild(scale, mt_steps, math.min(MAX_STEPS, mr_steps + 1), icon_idx) end
    )

    -- === QUICK PRESETS section ===
    local preset_btn_w = math.floor((inner_w - hspan * 2) / 3)
    local function selectedFilename()
        return (icon_idx > 0 and designs[icon_idx]) and designs[icon_idx].text or G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    end
    local function selectedIsRibbon()
        return isRibbonDesign(selectedFilename())
    end
    local preset_row = HorizontalGroup:new{
        align = "center",
        Button:new{
            text = _("Corner"),
            width = preset_btn_w,
            callback = function()
                rebuild(DEFAULT_NEW_SELECTION_SCALE, 0, 0, icon_idx)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text = _("Ribbon"),
            width = preset_btn_w,
            callback = function()
                rebuild(DEFAULT_RIBBON_SELECTION_SCALE, 0, DEFAULT_RIBBON_RIGHT_STEPS, icon_idx)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text = _("Tucked"),
            width = preset_btn_w,
            callback = function()
                if selectedIsRibbon() then
                    rebuild(2.3, 0, DEFAULT_RIBBON_RIGHT_STEPS, icon_idx)
                else
                    rebuild(3.0, 0, 1, icon_idx)
                end
            end,
        },
    }

    -- === ACTION buttons ===
    local act_btn_w = math.floor((inner_w - hspan * 2) / 3)
    local actions_row_top = HorizontalGroup:new{
        align = "center",
        Button:new{
            text = _("Set Day ☀"),
            width = act_btn_w,
            callback = function()
                self:saveCurrentAsDayPairCharm()
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text = _("Save"),
            width = act_btn_w,
            callback = function()
                self._slider_originals = nil
                UIManager:close(top_widget)
                UIManager:setDirty("all", "flashui")
                UIManager:scheduleIn(0, function()
                    UIManager:show(InfoMessage:new{ text = _("Charm updated."), timeout = 2 })
                end)
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text = _("Set Night ☾"),
            width = act_btn_w,
            callback = function()
                self:saveCurrentAsNightPairCharm()
            end,
        },
    }
    local actions_row_bottom = HorizontalGroup:new{
        align = "center",
        Button:new{
            text = _("Default"),
            width = act_btn_w,
            callback = function()
                self:setCurrentLookAsDefault()
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text = _("Reset"),
            width = act_btn_w,
            callback = function()
                self._slider_originals = nil
                UIManager:close(top_widget)
                UIManager:setDirty("all", "flashui")
                self:applyOriginalCorner(_("Original corner restored."))
            end,
        },
        HorizontalSpan:new{ width = hspan },
        Button:new{
            text = _("Cancel"),
            width = act_btn_w,
            callback = function()
                local orig = self._slider_originals
                if orig then
                    G_reader_settings:saveSetting(S_SCALE_FACTOR, orig.scale)
                    G_reader_settings:saveSetting(S_MARGIN_TOP,   orig.mt)
                    G_reader_settings:saveSetting(S_MARGIN_RIGHT, orig.mr)
                    if orig.icon then
                        G_reader_settings:saveSetting(S_CUSTOM_ICON,      orig.icon)
                        G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, orig.icon_name)
                    else
                        G_reader_settings:delSetting(S_CUSTOM_ICON)
                        G_reader_settings:delSetting(S_CUSTOM_ICON_NAME)
                    end
                    self:applyDogearToLive()
                    self._slider_originals = nil
                end
                UIManager:close(top_widget)
                UIManager:setDirty("all", "flashui")
            end,
        },
    }

    -- === Compose dialog: Bookmark Studio ===
    local card_pad = math.max(Size.padding.default, screenScaleBySize(10))
    local card_w = inner_w

    local header = VerticalGroup:new{
        align = "center",
        TextWidget:new{
            text = _("Charm Studio ✨"),
            face = Font:getFace("cfont", 24),
            bold = true,
        },
        VerticalSpan:new{ width = math.floor(vspan_sm / 2) },
        TextWidget:new{
            text = _("Choose a charm, set its size, then tuck it into place."),
            face = Font:getFace("smallinfofont", 15),
            max_width = inner_w,
        },
    }

    local design_card = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.default,
        radius = Size.radius.button,
        padding = card_pad,
        VerticalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = card_w - card_pad * 2, h = screenScaleBySize(24) },
                TextWidget:new{
                    text = _("Choose Your Mark ◈"),
                    face = Font:getFace("smallinfofont", 17),
                    bold = true,
                },
            },
            VerticalSpan:new{ width = vspan_sm },
            icon_row,
        },
    }

    local size_card = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.default,
        radius = Size.radius.button,
        padding = card_pad,
        VerticalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = card_w - card_pad * 2, h = screenScaleBySize(24) },
                TextWidget:new{
                    text = _("Charm Size ↕"),
                    face = Font:getFace("smallinfofont", 17),
                    bold = true,
                },
            },
            VerticalSpan:new{ width = vspan_sm },
            scale_row,
        },
    }

    local placement_card = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.default,
        radius = Size.radius.button,
        padding = card_pad,
        VerticalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = card_w - card_pad * 2, h = screenScaleBySize(24) },
                TextWidget:new{
                    text = _("Charm Placement ⌖"),
                    face = Font:getFace("smallinfofont", 17),
                    bold = true,
                },
            },
            VerticalSpan:new{ width = math.floor(vspan_sm / 2) },
            LeftContainer:new{
                dimen = Geom:new{ w = card_w - card_pad * 2, h = screenScaleBySize(36) },
                TextWidget:new{
                    text = _("Top and Right nudge the charm in small steps."),
                    face = Font:getFace("smallinfofont", 14),
                    max_width = card_w - card_pad * 2,
                },
            },
            VerticalSpan:new{ width = vspan_sm },
            top_margin_row,
            VerticalSpan:new{ width = vspan_sm },
            right_margin_row,
        },
    }

    local presets_card = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.default,
        radius = Size.radius.button,
        padding = card_pad,
        VerticalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = card_w - card_pad * 2, h = screenScaleBySize(24) },
                TextWidget:new{
                    text = _("Quick Presets ✦"),
                    face = Font:getFace("smallinfofont", 17),
                    bold = true,
                },
            },
            VerticalSpan:new{ width = vspan_sm },
            preset_row,
        },
    }

    local dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = pad,
        VerticalGroup:new{
            align = "center",
            header,
            VerticalSpan:new{ width = vspan_lg },
            design_card,
            VerticalSpan:new{ width = vspan_sm },
            size_card,
            VerticalSpan:new{ width = vspan_sm },
            placement_card,
            VerticalSpan:new{ width = vspan_sm },
            presets_card,
            VerticalSpan:new{ width = vspan_lg },
            actions_row_top,
            VerticalSpan:new{ width = vspan_sm },
            actions_row_bottom,
        },
    }

    top_widget = InputContainer:new{ modal = true, dimen = Screen:getSize() }
    top_widget[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        MovableContainer:new{ dialog_frame },
    }

    if Device:isTouchDevice() then
        function top_widget:onGesture(ev)
            if self[1] and self[1]:handleEvent(Event:new("Gesture", ev)) then
                return true
            end
            if ev.ges == "tap" and dialog_frame.dimen then
                if ev.pos:notIntersectWith(dialog_frame.dimen) then
                    UIManager:close(self)
                    UIManager:setDirty("all", "flashui")
                    return true
                end
            end
        end
    end

    UIManager:show(top_widget)
end

function BookmarkChrome:patchReaderDogear()
    local ok, err = pcall(function()
        local ReaderDogear = require("apps/reader/modules/readerdogear")

        if not ReaderDogear._dm_patched then
            ReaderDogear._dm_patched = true
            local orig_setupDogear = ReaderDogear.setupDogear
            local orig_resetLayout = ReaderDogear.resetLayout

            local function applyMarginOffset(rd_self)
                local mt_steps = G_reader_settings:readSetting(S_MARGIN_TOP) or 0
                local mr_steps = G_reader_settings:readSetting(S_MARGIN_RIGHT) or 0
                local mt = topStepsToPx(mt_steps)
                local mr = rightStepsToPx(mr_steps)

                if not (rd_self.vgroup and rd_self.icon and rd_self.top_pad) then return end

                -- Ribbon bookmarks should start at the very top.
                -- Dog-ears keep KOReader's normal dogear_y_offset.
                local current_icon_name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
                local is_ribbon_layout = current_icon_name and isRibbonDesign(current_icon_name)
                local top_offset = is_ribbon_layout and 0 or (rd_self.dogear_y_offset or 0)
                local icon_h = rd_self._bc_icon_height or rd_self.dogear_size

                -- Update main container dimensions
                if rd_self[1] and rd_self[1].dimen then
                    rd_self[1].dimen.w = Screen:getWidth()
                    rd_self[1].dimen.h = top_offset + icon_h + mt
                end

                -- Apply top margin (VerticalSpan uses .width for its size)
                rd_self.top_pad.width = top_offset + mt

                -- Apply right margin
                if mr > 0 then
                    -- Detach icon from old wrapper before freeing to avoid invalidation
                    if rd_self._dm_wrapper then
                        rd_self._dm_wrapper[1] = nil
                        rd_self._dm_wrapper:free()
                    end

                    rd_self._dm_wrapper = HorizontalGroup:new{
                        align = "top",
                        rd_self.icon,
                        HorizontalSpan:new{ width = mr },
                    }
                    rd_self.vgroup[2] = rd_self._dm_wrapper
                else
                    if rd_self._dm_wrapper then
                        rd_self._dm_wrapper[1] = nil
                        rd_self._dm_wrapper:free()
                        rd_self._dm_wrapper = nil
                    end
                    rd_self.vgroup[2] = rd_self.icon
                end

                rd_self.vgroup:resetLayout()
            end

            ReaderDogear.setupDogear = function(rd_self, new_dogear_size)
                local sf = G_reader_settings:readSetting(S_SCALE_FACTOR) or 1
                local icon_path = G_reader_settings:readSetting(S_CUSTOM_ICON)

                if sf ~= 1 then
                    if new_dogear_size then
                        new_dogear_size = math.ceil(new_dogear_size * sf)
                    elseif rd_self.dogear_max_size then
                        new_dogear_size = math.ceil(rd_self.dogear_max_size * sf)
                    end
                end

                -- Free old custom wrappers and icons before rebuilding
                if rd_self._dm_wrapper then
                    rd_self._dm_wrapper[1] = nil
                    rd_self._dm_wrapper:free()
                    rd_self._dm_wrapper = nil
                end
                if rd_self._dm_custom_icon then
                    rd_self._dm_custom_icon:free()
                    rd_self._dm_custom_icon = nil
                end
                if rd_self.icon and rd_self.icon.text == nil then
                    rd_self.icon:free()
                    rd_self.icon = nil
                end

                orig_setupDogear(rd_self, new_dogear_size)

                if icon_path and lfs.attributes(icon_path, "mode") == "file" and rd_self.icon then
                    local filename = icon_path and icon_path:match("([^/]+)$")
                    local is_ribbon = filename and isRibbonDesign(filename)
                    local is_night_ribbon = filename and filename:lower():match("^ribbon_night_") ~= nil
                    local is_night_dogear = filename and filename:lower():match("^dogear_night_") ~= nil

                    if is_ribbon then
                        -- Ribbons are naturally tall bookmarks, not square dog-ears.
                        -- This keeps all ribbons larger and lets them sit at the top.
                        local ribbon_w = math.floor(rd_self.dogear_size * 0.85)
                        local ribbon_h = math.floor(rd_self.dogear_size * 1.35)
                        rd_self.icon = ImageWidget:new{
                            file   = icon_path,
                            width  = ribbon_w,
                            height = ribbon_h,
                            -- Night ribbons must be opaque so KOReader does not
                            -- render transparent padding as a white box in night mode.
                            alpha  = not is_night_ribbon,
                        }
                        rd_self._bc_icon_height = ribbon_h
                    else
                        rd_self.icon = ImageWidget:new{
                            file   = icon_path,
                            width  = rd_self.dogear_size,
                            height = rd_self.dogear_size,
                            alpha  = not is_night_dogear,
                        }
                        rd_self._bc_icon_height = rd_self.dogear_size
                    end

                    rd_self._dm_custom_icon = rd_self.icon
                end

                applyMarginOffset(rd_self)
            end

            if orig_resetLayout then
                ReaderDogear.resetLayout = function(rd_self, ...)
                    orig_resetLayout(rd_self, ...)
                    applyMarginOffset(rd_self)
                end
            end

            local orig_updateDogearOffset = ReaderDogear.updateDogearOffset
            if orig_updateDogearOffset then
                ReaderDogear.updateDogearOffset = function(rd_self, ...)
                    orig_updateDogearOffset(rd_self, ...)
                    applyMarginOffset(rd_self)
                end
            end
        end
    end)

    if not ok then
        logger.err("BookmarkChrome: patchReaderDogear failed:", err)
    end
    self:applyDogearToLive()
end


function BookmarkChrome:onDispatcherRegisterActions()
    safeRegisterAction("booknook_charm_studio", { category="none", event="BookNookCharmStudio", title=_("Book Nook Charms: Charm Studio"), reader=true })
    safeRegisterAction("booknook_charm_library", { category="none", event="BookNookCharmLibrary", title=_("Book Nook Charms: Charm Library"), reader=true })
    safeRegisterAction("booknook_favorite_charms", { category="none", event="BookNookFavoriteCharms", title=_("Book Nook Charms: Favorite Charms"), reader=true })
    safeRegisterAction("booknook_next_favorite_charm", { category="none", event="BookNookNextFavoriteCharm", title=_("Book Nook Charms: Next favorite charm"), reader=true })
    safeRegisterAction("booknook_charm_types", { category="none", event="BookNookCharmTypes", title=_("Book Nook Charms: Charm Types"), reader=true })
    safeRegisterAction("booknook_switch_day_night", { category="none", event="BookNookSwitchDayNight", title=_("Book Nook Charms: Switch day/night charm"), reader=true })
    safeRegisterAction("booknook_apply_day_charm", { category="none", event="BookNookApplyDayCharm", title=_("Book Nook Charms: Apply day charm"), reader=true })
    safeRegisterAction("booknook_apply_night_charm", { category="none", event="BookNookApplyNightCharm", title=_("Book Nook Charms: Apply night charm"), reader=true })
    safeRegisterAction("booknook_toggle_auto_pair", { category="none", event="BookNookToggleAutoPair", title=_("Book Nook Charms: Toggle auto day/night"), reader=true })
    safeRegisterAction("booknook_reset_charm", { category="none", event="BookNookResetCharm", title=_("Book Nook Charms: Reset charm"), reader=true })
end


function BookmarkChrome:ensureReaderAction()
    if self.ui and self.ui.view then return true end
    UIManager:show(InfoMessage:new{ text = _("Open a book first to use Book Nook Charms."), timeout = 2 })
    return false
end

function BookmarkChrome:onBookNookCharmStudio()
        if not self:ensureReaderAction() then return true end
self:showSizeSlider()
    return true
end

function BookmarkChrome:onBookNookCharmLibrary()
        if not self:ensureReaderAction() then return true end
self:showDesignMenu()
    return true
end

function BookmarkChrome:onBookNookFavoriteCharms()
        if not self:ensureReaderAction() then return true end
self:showFavoriteLooksMenu()
    return true
end

function BookmarkChrome:onBookNookNextFavoriteCharm()
        if not self:ensureReaderAction() then return true end
self:applyNextFavoriteCharm()
    return true
end

function BookmarkChrome:onBookNookCharmTypes()
        if not self:ensureReaderAction() then return true end
self:showCharmTypesMenu()
    return true
end

function BookmarkChrome:onBookNookSwitchDayNight()
        if not self:ensureReaderAction() then return true end
self:switchDayNightPair()
    return true
end

function BookmarkChrome:onBookNookApplyDayCharm()
        if not self:ensureReaderAction() then return true end
self:applyPairCharm("day")
    return true
end

function BookmarkChrome:onBookNookApplyNightCharm()
        if not self:ensureReaderAction() then return true end
self:applyPairCharm("night")
    return true
end

function BookmarkChrome:onBookNookToggleAutoPair()
        if not self:ensureReaderAction() then return true end
self:toggleAutoDayNightPair()
    return true
end

function BookmarkChrome:onBookNookResetCharm()
        if not self:ensureReaderAction() then return true end
self:resetAll()
    UIManager:show(InfoMessage:new{ text = _("Book Nook Charms restored."), timeout = 2 })
    return true
end


function BookmarkChrome:init()
    self:onDispatcherRegisterActions()
    if self.ui and self.ui.view and self.ui.menu then
        self._booknook_menu_registered = safeRegisterMainMenu(self)
    end
end

function BookmarkChrome:onReaderReady()
    if not self._booknook_menu_registered and self.ui and self.ui.menu then
        self._booknook_menu_registered = safeRegisterMainMenu(self)
    end
    self:ensureAutoPairDefaultOff()
    self:patchReaderDogear()
    local restored_book = self:applyBookLook(false)
    if not restored_book then
        self:applyFirstRunDefault()
    end
    self:applyAutoDayNightPair(false)
    self:startAutoDayNightWatcher()
end


function BookmarkChrome:saveCurrentAsDayPairCharm()
    local icon = G_reader_settings:readSetting(S_CUSTOM_ICON)
    local name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    local resolved_name, resolved_path = self:resolveSavedDesign(icon, name)
    if not resolved_path or not resolved_name then
        UIManager:show(InfoMessage:new{ text = _("No charm is selected yet."), timeout = 2 })
        return
    end
    G_reader_settings:saveSetting(S_CUSTOM_ICON, resolved_path)
    G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, resolved_name)
    G_reader_settings:saveSetting(S_DAY_PAIR_ICON, resolved_path)
    G_reader_settings:saveSetting(S_DAY_PAIR_NAME, resolved_name)
    G_reader_settings:saveSetting(S_DAY_PAIR_SCALE, G_reader_settings:readSetting(S_SCALE_FACTOR) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_SELECTION_SCALE or DEFAULT_NEW_SELECTION_SCALE))
    G_reader_settings:saveSetting(S_DAY_PAIR_TOP, G_reader_settings:readSetting(S_MARGIN_TOP) or 0)
    G_reader_settings:saveSetting(S_DAY_PAIR_RIGHT, G_reader_settings:readSetting(S_MARGIN_RIGHT) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_RIGHT_STEPS or 0))
    UIManager:show(InfoMessage:new{ text = _("Day charm saved ☀"), timeout = 2 })
end

function BookmarkChrome:saveCurrentAsNightPairCharm()
    local icon = G_reader_settings:readSetting(S_CUSTOM_ICON)
    local name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    local resolved_name, resolved_path = self:resolveSavedDesign(icon, name)
    if not resolved_path or not resolved_name then
        UIManager:show(InfoMessage:new{ text = _("No charm is selected yet."), timeout = 2 })
        return
    end
    G_reader_settings:saveSetting(S_CUSTOM_ICON, resolved_path)
    G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, resolved_name)
    G_reader_settings:saveSetting(S_NIGHT_PAIR_ICON, resolved_path)
    G_reader_settings:saveSetting(S_NIGHT_PAIR_NAME, resolved_name)
    G_reader_settings:saveSetting(S_NIGHT_PAIR_SCALE, G_reader_settings:readSetting(S_SCALE_FACTOR) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_SELECTION_SCALE or DEFAULT_NEW_SELECTION_SCALE))
    G_reader_settings:saveSetting(S_NIGHT_PAIR_TOP, G_reader_settings:readSetting(S_MARGIN_TOP) or 0)
    G_reader_settings:saveSetting(S_NIGHT_PAIR_RIGHT, G_reader_settings:readSetting(S_MARGIN_RIGHT) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_RIGHT_STEPS or 0))
    UIManager:show(InfoMessage:new{ text = _("Night charm saved ☾"), timeout = 2 })
end

function BookmarkChrome:applyPairCharm(which, silent)
    local icon_key, name_key, scale_key, top_key, right_key, label
    if which == "night" then
        icon_key, name_key, scale_key, top_key, right_key = S_NIGHT_PAIR_ICON, S_NIGHT_PAIR_NAME, S_NIGHT_PAIR_SCALE, S_NIGHT_PAIR_TOP, S_NIGHT_PAIR_RIGHT
        label = _("Night charm applied ☾")
    else
        icon_key, name_key, scale_key, top_key, right_key = S_DAY_PAIR_ICON, S_DAY_PAIR_NAME, S_DAY_PAIR_SCALE, S_DAY_PAIR_TOP, S_DAY_PAIR_RIGHT
        label = _("Day charm applied ☀")
    end

    local icon = G_reader_settings:readSetting(icon_key)
    local name = G_reader_settings:readSetting(name_key)
    local resolved_name, resolved_path, repaired = self:resolveSavedDesign(icon, name)
    if not resolved_path or not resolved_name then
        if icon or name then
            G_reader_settings:delSetting(icon_key)
            G_reader_settings:delSetting(name_key)
            G_reader_settings:delSetting(scale_key)
            G_reader_settings:delSetting(top_key)
            G_reader_settings:delSetting(right_key)
            if not silent then
                UIManager:show(InfoMessage:new{ text = _("Saved pair charm was missing, so it was cleared."), timeout = 2 })
            end
        end
        return false
    end
    if repaired then
        G_reader_settings:saveSetting(icon_key, resolved_path)
        G_reader_settings:saveSetting(name_key, resolved_name)
    end

    self:applyLook(resolved_name, resolved_path,
        G_reader_settings:readSetting(scale_key) or (isRibbonDesign(resolved_name) and DEFAULT_RIBBON_SELECTION_SCALE or DEFAULT_NEW_SELECTION_SCALE),
        G_reader_settings:readSetting(top_key) or 0,
        G_reader_settings:readSetting(right_key) or (isRibbonDesign(name) and DEFAULT_RIBBON_RIGHT_STEPS or 0),
        false,
        label)
    return true
end

function BookmarkChrome:switchDayNightPair()
    local current = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    local day_name = G_reader_settings:readSetting(S_DAY_PAIR_NAME)
    local night_name = G_reader_settings:readSetting(S_NIGHT_PAIR_NAME)

    if current and day_name and current == day_name then
        self:applyPairCharm("night", true)
    elseif current and night_name and current == night_name then
        self:applyPairCharm("day", true)
    elseif night_name then
        self:applyPairCharm("night", true)
    else
        self:applyPairCharm("day", true)
    end
end


function BookmarkChrome:isNightModeActive()
    -- KOReader stores the active night-mode switch in reader settings.
    -- ["night_mode"] is the active KOReader night-mode switch.
    return G_reader_settings:readSetting("night_mode") == true
end


function BookmarkChrome:ensureAutoPairDefaultOff()
    if G_reader_settings:readSetting(S_AUTO_PAIR_SWITCH) == nil then
        G_reader_settings:saveSetting(S_AUTO_PAIR_SWITCH, false)
    end
end

function BookmarkChrome:autoPairEnabled()
    -- Default OFF unless the user explicitly turns Auto Pair on.
    return G_reader_settings:readSetting(S_AUTO_PAIR_SWITCH) == true
end

function BookmarkChrome:toggleAutoDayNightPair()
    if self:autoPairEnabled() then
        G_reader_settings:saveSetting(S_AUTO_PAIR_SWITCH, false)
        UIManager:show(InfoMessage:new{ text = _("Auto Day/Night Pair off."), timeout = 2 })
    else
        G_reader_settings:saveSetting(S_AUTO_PAIR_SWITCH, true)
        UIManager:show(InfoMessage:new{ text = _("Auto Day/Night Pair on."), timeout = 2 })
        self:applyAutoDayNightPair(false)
    end
end

function BookmarkChrome:applyAutoDayNightPair(force)
    if not self:autoPairEnabled() then return false end

    local want = self:isNightModeActive() and "night" or "day"
    local last = G_reader_settings:readSetting(S_LAST_PAIR_MODE)

    -- Do not repeatedly reapply on every redraw.
    if not force and last == want then
        return false
    end

    local ok = self:applyPairCharm(want, true)
    if ok then
        G_reader_settings:saveSetting(S_LAST_PAIR_MODE, want)
    end
    return ok
end



function BookmarkChrome:startAutoDayNightWatcher()
    if self._auto_daynight_watcher_running then
        return
    end

    self._auto_daynight_watcher_running = true

    local function tick()
        -- Lightweight watcher: only applies when night_mode changes.
        if self.autoPairEnabled and self:autoPairEnabled() then
            self:applyAutoDayNightPair(false)
        end

        UIManager:scheduleIn(1.5, tick)
    end

    UIManager:scheduleIn(1.5, tick)
end


function BookmarkChrome:showDayNightPairMenu()
    local pair_menu
    pair_menu = Menu:new{
        title = _("Day/Night Pair ☀☾"),
        item_table = {
            {
                text = _("Set Current as Day Charm ☀"),
                callback = function()
                    UIManager:close(pair_menu)
                    self:saveCurrentAsDayPairCharm()
                end,
            },
            {
                text = _("Set Current as Night Charm ☾"),
                callback = function()
                    UIManager:close(pair_menu)
                    self:saveCurrentAsNightPairCharm()
                end,
            },
            {
                text = _("Switch Day/Night Pair ☀☾"),
                callback = function()
                    UIManager:close(pair_menu)
                    self:switchDayNightPair()
                end,
            },
            {
                text = self:autoPairEnabled() and _("Auto Pair: On") or _("Auto Pair: Off"),
                callback = function()
                    UIManager:close(pair_menu)
                    self:toggleAutoDayNightPair()
                end,
            },
            {
                text = _("Apply Auto Pair Now"),
                callback = function()
                    UIManager:close(pair_menu)
                    self:applyAutoDayNightPair(true)
                end,
            },
        },
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() UIManager:close(pair_menu) end,
    }
    UIManager:show(pair_menu)
end




function BookmarkChrome:displayLibraryTypeLabel(filename)
    local label = displayCharmName(filename)
    if self:isFavoriteDesign(filename) then
        label = label .. " ⭐"
    end
    if isRibbonDesign(filename) then
        return charmPreviewPrefix(filename) .. _("Ribbon") .. " — " .. label
    end
    return charmPreviewPrefix(filename) .. _("Dogear") .. " — " .. label
end

function BookmarkChrome:buildCharmLibraryItems()
    local items = {}
    local designs = self:scanDesigns()

    for __, design in ipairs(designs) do
        table.insert(items, {
            text = self:displayLibraryTypeLabel(design.text),
            keep_menu_open = true,
            callback = function()
                self:applyDesign(design.text, design.path)
            end,
        })
    end

    if #items == 0 then
        table.insert(items, { text = _("No charms found"), enabled = false })
    end

    table.insert(items, {
        text = _("Restore Original Corner"),
        keep_menu_open = false,
        callback = function()
            self:resetAll()
            UIManager:show(InfoMessage:new{ text = _("Default dog-ear restored."), timeout = 2 })
        end,
    })

    return items
end

function BookmarkChrome:refreshFavoriteCharmItems()
    if not self._favorite_charm_items then return end

    local fresh = self:buildFavoriteCharmItems(true)
    for i = #self._favorite_charm_items, 1, -1 do
        self._favorite_charm_items[i] = nil
    end
    for i, item in ipairs(fresh) do
        self._favorite_charm_items[i] = item
    end
end

function BookmarkChrome:buildFavoriteCharmItems(skip_reference_update)
    local items = {}
    local designs = self:scanDesigns()
    local favorites = self:getFavoriteDesigns()

    for __, filename in ipairs(favorites) do
        local design = self:findDesignByName(filename, designs)
        if design then
            table.insert(items, {
                text = self:displayMenuLabel(design.text),
                keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        else
            table.insert(items, {
                text = _("Missing charm") .. " — " .. tostring(filename),
                enabled = false,
            })
        end
    end

    if #favorites == 0 then
        table.insert(items, { text = _("No favorites yet"), enabled = false })
    end

    table.insert(items, {
        text = _("Add Current Charm ⭐"),
        keep_menu_open = false,
        callback = function() self:addCurrentToFavorites() end,
    })
    table.insert(items, {
        text = _("Remove Current Charm"),
        keep_menu_open = false,
        callback = function() self:removeCurrentFromFavorites() end,
    })
    table.insert(items, {
        text = _("Next Favorite Charm"),
        keep_menu_open = false,
        callback = function() self:applyNextFavoriteCharm() end,
    })
    table.insert(items, {
        text = _("Clear Favorite Charms"),
        keep_menu_open = false,
        callback = function() self:clearFavorites() end,
    })

    if self:countMissingFavorites(designs) > 0 then
        table.insert(items, {
            text = _("Remove Missing Favorites"),
            keep_menu_open = false,
            callback = function() self:pruneMissingFavorites(true) end,
        })
    end

    if not skip_reference_update then
        self._favorite_charm_items = items
    end

    return items
end


function BookmarkChrome:buildCornerCharmItems()
    local items = {}
    local designs = self:scanDesigns()

    for __, design in ipairs(designs) do
        if not isRibbonDesign(design.text) then
            table.insert(items, {
                text = self:displayMenuLabel(design.text),
                keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    if #items == 0 then
        table.insert(items, { text = _("No corner charms found"), enabled = false })
    end

    return items
end


function BookmarkChrome:buildRibbonCharmItems()
    local items = {}
    local designs = self:scanDesigns()

    for __, design in ipairs(designs) do
        if isRibbonDesign(design.text) then
            table.insert(items, {
                text = self:displayMenuLabel(design.text),
                keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    if #items == 0 then
        table.insert(items, { text = _("No ribbon charms found"), enabled = false })
    end

    return items
end


function BookmarkChrome:buildNightCharmItems()
    local items = {}
    local designs = self:scanDesigns()
    local added = {}

    for __, look in ipairs(NIGHT_LOOKS) do
        local design = self:findDesignByName(look.file, designs)
        if design and not added[design.text] then
            added[design.text] = true
            table.insert(items, {
                text = self:displayMenuLabel(design.text),
                keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    local custom_night = {}
    local seen = {}
    scanDir(self:getPluginNightDir(), custom_night, seen)
    scanDir(self:getDataNightDir(), custom_night, seen)
    table.sort(custom_night, function(a, b) return a.text < b.text end)

    for __, design in ipairs(custom_night) do
        if not added[design.text] then
            added[design.text] = true
            table.insert(items, {
                text = self:displayMenuLabel(design.text),
                keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    if #items == 0 then
        table.insert(items, { text = _("No night charms found"), enabled = false })
    end

    return items
end


function BookmarkChrome:buildEInkCharmItems()
    local items = {}
    local designs = self:scanDesigns()
    local added = {}

    for __, look in ipairs(EINK_LOOKS) do
        local design = self:findDesignByName(look.file, designs)
        if design and not added[design.text] then
            added[design.text] = true
            table.insert(items, {
                text = self:displayEInkMenuLabel(design.text, look.label),
                keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    for __, design in ipairs(designs) do
        if isEInkDesign(design.text) and not added[design.text] then
            added[design.text] = true
            table.insert(items, {
                text = self:displayEInkMenuLabel(design.text),
                keep_menu_open = true,
                callback = function()
                    self:applyDesign(design.text, design.path)
                end,
            })
        end
    end

    if #items == 0 then
        table.insert(items, { text = _("No e-ink charms found"), enabled = false })
    end

    return items
end


function BookmarkChrome:buildCharmTypeItems()
    return {
        {
            text = _("Ribbon Charms ✿"),
            keep_menu_open = true,
            sub_item_table = self:buildRibbonCharmItems(),
        },
        {
            text = _("Corner Charms ❖"),
            keep_menu_open = true,
            sub_item_table = self:buildCornerCharmItems(),
        },
        {
            text = _("Night Charms ☾"),
            keep_menu_open = true,
            sub_item_table = self:buildNightCharmItems(),
        },
        {
            text = _("E-ink Charms ◐"),
            keep_menu_open = true,
            sub_item_table = self:buildEInkCharmItems(),
        },
    }
end


function BookmarkChrome:buildDayNightPairItems()
    return {
        {
            text = _("Set Current as Day Charm ☀"),
            keep_menu_open = false,
            callback = function() self:saveCurrentAsDayPairCharm() end,
        },
        {
            text = _("Set Current as Night Charm ☾"),
            keep_menu_open = false,
            callback = function() self:saveCurrentAsNightPairCharm() end,
        },
        {
            text = _("Switch Day/Night Pair ☀☾"),
            keep_menu_open = false,
            callback = function() self:switchDayNightPair() end,
        },
        {
            text = self:autoPairEnabled() and _("Auto Pair: On") or _("Auto Pair: Off"),
            keep_menu_open = false,
            callback = function() self:toggleAutoDayNightPair() end,
        },
        {
            text = _("Apply Auto Pair Now"),
            keep_menu_open = false,
            callback = function() self:applyAutoDayNightPair(true) end,
        },
    }
end



function BookmarkChrome:buildSetCharmItems()
    return {
        {
            text = _("Save Charm to This Book ✓"),
            keep_menu_open = false,
            callback = function()
                self:saveCurrentLookToBook()
            end,
        },
        {
            text = _("Set as Default ✧"),
            keep_menu_open = false,
            callback = function()
                self:setCurrentLookAsDefault()
            end,
        },
        {
            text = _("Reset Charms ↺"),
            keep_menu_open = false,
            callback = function()
                self:resetAll()
                UIManager:show(InfoMessage:new{ text = _("Book Nook Charms restored."), timeout = 2 })
            end,
        },
    }
end

function BookmarkChrome:showHelp()
    UIManager:show(InfoMessage:new{
        text = _("Book Nook Charms\n\nCharm Studio: resize and place your charm.\nCharm Library: browse all charms together.\nFavorite Charms: save your sweetest picks.\nCharm Types: browse ribbons, dog-ears, night charms, and e-ink charms.\nDay/Night Pair: choose one charm for day and one for night.\nSet a Charm: save, reset, or set defaults.\n\nE-ink charms are grayscale on purpose for black-and-white e-readers."),
    })
end

function BookmarkChrome:showTroubleshooting()
    local current_name = G_reader_settings:readSetting(S_CUSTOM_ICON_NAME)
    local current_path = G_reader_settings:readSetting(S_CUSTOM_ICON)
    local resolved_name, resolved_path, repaired = self:resolveSavedDesign(current_path, current_name)
    if repaired then
        G_reader_settings:saveSetting(S_CUSTOM_ICON, resolved_path)
        G_reader_settings:saveSetting(S_CUSTOM_ICON_NAME, resolved_name)
    end

    local ds = self.ui and self.ui.doc_settings
    local book_name = ds and ds:readSetting(B_CUSTOM_ICON_NAME) or nil
    local book_path = ds and ds:readSetting(B_CUSTOM_ICON) or nil
    local book_resolved = nil
    if ds then
        book_resolved = self:resolveSavedDesign(book_path, book_name) ~= nil
    end

    local default_name = G_reader_settings:readSetting(S_DEFAULT_ICON_NAME)
    local default_path = G_reader_settings:readSetting(S_DEFAULT_ICON)
    local default_resolved = self:resolveSavedDesign(default_path, default_name) ~= nil
    local day_resolved = self:resolveSavedDesign(G_reader_settings:readSetting(S_DAY_PAIR_ICON), G_reader_settings:readSetting(S_DAY_PAIR_NAME)) ~= nil
    local night_resolved = self:resolveSavedDesign(G_reader_settings:readSetting(S_NIGHT_PAIR_ICON), G_reader_settings:readSetting(S_NIGHT_PAIR_NAME)) ~= nil

    local function yesno(value)
        return value and _("yes") or _("no")
    end

    UIManager:show(InfoMessage:new{
        text = _("Book Nook Charms Troubleshooting")
            .. "\n\n" .. _("Version") .. ": " .. PLUGIN_VERSION
            .. "\n" .. _("Current charm") .. ": " .. (resolved_name or current_name or _("none"))
            .. "\n" .. _("Current file found") .. ": " .. yesno(resolved_path ~= nil)
            .. "\n" .. _("Default charm found") .. ": " .. yesno(default_resolved)
            .. "\n" .. _("Book charm found") .. ": " .. yesno(book_resolved)
            .. "\n" .. _("Day pair found") .. ": " .. yesno(day_resolved)
            .. "\n" .. _("Night pair found") .. ": " .. yesno(night_resolved)
            .. "\n" .. _("Auto pair") .. ": " .. (self:autoPairEnabled() and _("on") or _("off"))
            .. "\n" .. _("Scale") .. ": " .. tostring(G_reader_settings:readSetting(S_SCALE_FACTOR) or DEFAULT_NEW_SELECTION_SCALE)
            .. "\n" .. _("Top / Right") .. ": " .. tostring(G_reader_settings:readSetting(S_MARGIN_TOP) or 0) .. " / " .. tostring(G_reader_settings:readSetting(S_MARGIN_RIGHT) or 0),
    })
end

function BookmarkChrome:showCharmTypesMenu()
    local charm_types_menu
    charm_types_menu = Menu:new{
        title = _("Charm Types ◇"),
        item_table = self:buildCharmTypeItems(),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() UIManager:close(charm_types_menu) end,
    }
    UIManager:show(charm_types_menu)
end

function BookmarkChrome:addToMainMenu(menu_items)
    menu_items.booknookcharms = {
        text = _("Book Nook Charms"),
        sorting_hint = "typeset",
        sub_item_table = {
            {
                text = _("Charm Studio ✨"),
                keep_menu_open = false,
                callback = function() self:showSizeSlider() end,
            },
            {
                text = _("Charm Library ❤"),
                sub_item_table = self:buildCharmLibraryItems(),
            },
            {
                text = _("Favorite Charms ⭐"),
                keep_menu_open = true,
                sub_item_table = self:buildFavoriteCharmItems(),
            },
            {
                text = _("Charm Types ◇"),
                keep_menu_open = true,
                sub_item_table = self:buildCharmTypeItems(),
            },
            {
                text = _("Day/Night Pair ☀☾"),
                sub_item_table = self:buildDayNightPairItems(),
            },
            {
                text = _("Set a Charm ✧"),
                sub_item_table = self:buildSetCharmItems(),
            },
            {
                text = _("Troubleshooting ⚙"),
                keep_menu_open = false,
                callback = function() self:showTroubleshooting() end,
            },
            {
                text = _("Help ✎"),
                keep_menu_open = false,
                callback = function() self:showHelp() end,
            },
            {
                text = _("About ⓘ"),
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = _("Version") .. " " .. PLUGIN_VERSION,
                        bold = true,
                        keep_menu_open = true,
                        callback = function() end,
                    },
                    {
                        text = _("Made By") .. " " .. PLUGIN_AUTHOR,
                        bold = true,
                        keep_menu_open = true,
                        callback = function() end,
                    },
                },
            },
        },
    }
end

return BookmarkChrome








