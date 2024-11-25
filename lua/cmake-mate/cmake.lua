local scandir = require('plenary.scandir')
local Path = require('plenary.path')

local function get_codemodel_targets(build_dir)
    if not build_dir:is_dir() then
        return {}
    end

    local reply_dir = build_dir / '.cmake' / 'api' / 'v1' / 'reply'
    local found_files = scandir.scan_dir(reply_dir.filename, {
        search_pattern = 'codemodel*'
    })
    if #found_files == 0 then
        return {}
    end

    local codemodel = Path:new(found_files[1])
    local codemodel_json = vim.json.decode(codemodel:read())
    return codemodel_json['configurations'][1]['targets']
end


local M = {}


function M.get_executable_target_path(build_dir, target_json)
    if not build_dir:is_dir() then
        return nil
    end

    -- https://cmake.org/cmake/help/latest/manual/cmake-file-api.7.html#api-v1
    local reply_dir = build_dir / '.cmake' / 'api' / 'v1' / 'reply'
    local target_info = vim.json.decode((reply_dir / target_json):read())

    local type = target_info["type"]:lower():gsub("_", " ")
    if type ~= "executable" then
        print("Selected target is not executable")
        return nil
    end

    local target_path = target_info["artifacts"][1]["path"]

    target_path = Path:new(target_path)

    if not target_path:is_absolute() then
        target_path = build_dir / target_path
    end

    -- if not target_path:is_file() then
    --     print(string.format("Target is not yet built: %s", target_path))
    --     return nil
    -- end

    return target_path
end


function M.get_all_executable_targets(build_dir)
    local all_targets = get_codemodel_targets(Path:new(build_dir))
    local exe_targets = {}

    for _, t in ipairs(all_targets) do
        -- local type = t.type:lower():gsub("_", " ")
        -- if type == "executable" then
        table.insert(exe_targets, t)
        -- end
    end
    return exe_targets
end


return M
