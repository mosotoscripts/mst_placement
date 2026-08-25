local _localeCache = { lang = nil, primary = nil, en = nil }

function MST_PlacementGetBridgeLanguage()
    local file = LoadResourceFile('mst_bridge', 'config.lua')
    if not file then return 'en' end
    local lang = file:match("Config%.Language%s*=%s*['\"]([%w_%-]+)['\"]")
    return lang or 'en'
end

local function loadLocaleJson(lang)
    if type(lang) ~= 'string' or lang == '' then return nil end
    local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(lang))
    if not raw or raw == '' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then return decoded end
    return nil
end

local function nestedValue(tbl, keyPath)
    if type(tbl) ~= 'table' or type(keyPath) ~= 'string' or keyPath == '' then return nil end
    local node = tbl
    for part in string.gmatch(keyPath, '[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    return node
end

function MST_PlacementGetLocaleTable()
    local lang = MST_PlacementGetBridgeLanguage()
    if _localeCache.lang == lang and type(_localeCache.primary) == 'table' then
        return _localeCache.primary
    end
    _localeCache.lang = lang
    _localeCache.primary = loadLocaleJson(lang) or loadLocaleJson('en') or {}
    if type(_localeCache.en) ~= 'table' then
        _localeCache.en = loadLocaleJson('en') or {}
    end
    return _localeCache.primary
end

local function getEnLocaleTable()
    MST_PlacementGetLocaleTable()
    return _localeCache.en or {}
end

function MST_PlacementLocale(keyPath)
    if type(keyPath) ~= 'string' or keyPath == '' then return '' end
    local val = nestedValue(MST_PlacementGetLocaleTable(), keyPath)
    if type(val) == 'string' and val ~= '' then return val end
    val = nestedValue(getEnLocaleTable(), keyPath)
    if type(val) == 'string' and val ~= '' then return val end
    return keyPath
end