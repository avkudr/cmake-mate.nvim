local overseer = require("overseer")
local scandir = require('plenary.scandir')

local Path = require('plenary.path')
local cmake = require('cmake-mate.cmake')

local data_path = Path:new(vim.fn.stdpath("data"))
local workspace_id = vim.fn.sha256(vim.fn.getcwd() .. vim.env.USER)
local workspace_config_dir = data_path / "cmake-mate" / workspace_id
local workspace_config_file = workspace_config_dir / "cmake-mate.json"

local function read_config()
    if not workspace_config_dir:exists() then
        Path:new(workspace_config_dir):mkdir({parents = true})
        return {}
    end

    if not workspace_config_file:exists() then
        return {}
    end

    return vim.fn.json_decode(Path:new(workspace_config_file):read())
end

local function store_current_target(current_target)
    local data = read_config()
    data.current_target = current_target
    Path:new(workspace_config_file):write(vim.fn.json_encode(data), "w")
end

local target_run_default_config = [[
-- This file contains the parameters that will be passed to the executable
-- make sure to save it for changes to be taken into account
return {
    args = nil,
    cwd = nil,
}
]]

local function get_target_config_file(target_name)
    return Path:new(data_path / "cmake-mate" / workspace_id / (target_name .. ".lua"))
end

local function get_target_config(target_name)
    local file = get_target_config_file(target_name)
    if not file:exists() then
        return nil
    end

    return dofile(file.filename)
end

local function parse_args(input)
    -- "--arg 1 --lala 2" -> {"--arg", "1", "--lala", "2"}
    local args = {}
    for arg in input:gmatch("%S+") do
        table.insert(args, arg)
    end
    return args
end

local _config = {
    build_dir = nil,
    current_target = nil,
}

local function create_run_task(checks)
    checks = checks or False
    if _config.current_target == nil then
        print("No cmake target selected. Use CMakeSelectTarget first")
        return
    end

    local executable = cmake.get_executable_target_path(
        Path:new(_config.build_dir), _config.current_target.jsonFile)

    if checks and (executable == nil or not executable:exists()) then
        print("Executable doesn't exist " .. executable)
        return
    end

    local task_config = {
        command = executable.filename,
        args = {},
        cwd = executable:parent().filename,
    }

    local cache = get_target_config(_config.current_target.name)
    if cache then
        for key, value in pairs(cache) do
            if value then
                task_config[key] = value
            end
        end
    end

    if task_config.args and type(task_config.args) == "string" then
        task_config.args = parse_args(task_config.args)
    end

    return {
        cmd = task_config.command,
        args = task_config.args,
        cwd = task_config.cwd,
        components = { { "open_output", on_start = "always" }, "default", { "unique", replace = true } }
    }
end

local M = {}

function M.get_current_target_name()
    if _config.current_target then
        return _config.current_target.name
    end
    return ""
end

function M.setup(config)
    if not config then
        config = {}
    end

    local s_config = read_config()
    if s_config then
        _config = s_config
    end

    local current_dir = vim.fn.getcwd()
    _config.build_dir = vim.loop.fs_realpath(current_dir .. "/../build-relwithdebinfo")

    vim.api.nvim_create_user_command("CMakeClean", function()
        local task = overseer.new_task({
            cmd = "cmake",
            args = { '--build', _config.build_dir, "--target", "clean"},
            components = { { "on_output_quickfix", open = false }, { "open_output", on_start = "always" }, "default", { "unique", replace = true } }
        })
        task:start()
    end, {})

    vim.api.nvim_create_user_command("CMakeGenerate", function()
        local task = overseer.new_task({
            cmd = "cmake",
            args = { '-B', _config.build_dir, "-DCMAKE_BUILD_TYPE=RelWithDebInfo", "-DCMAKE_EXPORT_COMPILE_COMMANDS=1"},
            components = { { "on_output_quickfix", open = false }, { "open_output", on_start = "always" }, "default", { "unique", replace = true } }
        })
        task:start()
    end, {})

    vim.api.nvim_create_user_command("CMakeBuildAll", function()
        local nb_jobs = 250

        local task = overseer.new_task({
            cmd = "cmake",
            args = { '--build', '.', '-j', tostring(nb_jobs), '--target', 'all' },
            cwd = _config.build_dir,
            components = { { "on_output_quickfix", open = false }, { "open_output", on_start = "always" }, "default", { "unique", replace = true } }
        })
        task:start()
    end, {})

    vim.api.nvim_create_user_command("CMakeBuildCurrent", function()
        local nb_jobs = 250

        if _config.current_target == nil then
            print("No cmake target selected. Use CMakeSelectTarget first")
            return
        end

        local task = overseer.new_task({
            cmd = "cmake",
            args = { '--build', '.', '--target', _config.current_target.name, '-j', tostring(nb_jobs) },
            cwd = _config.build_dir,
            components = { { "on_output_quickfix", open = false }, { "open_output", on_start = "always" }, "default", { "unique", replace = true } }
        })
        task:start()
    end, {})

    vim.api.nvim_create_user_command("CMakeBuildCurrentAndRun", function()
        local nb_jobs = 250

        if _config.current_target == nil then
            print("No cmake target selected. Use CMakeSelectTarget first")
            return
        end

        local task = overseer.new_task({
            name = string.format("Build and Run: %s", _config.current_target.name),
            strategy = {
                "orchestrator",
                tasks = {
                    {
                        cmd = "cmake",
                        args = { '--build', '.', '--target', _config.current_target.name, '-j', tostring(nb_jobs) },
                        cwd = _config.build_dir,
                        components = { { "on_output_quickfix", open = false }, { "open_output", on_start = "always" }, "default", { "unique", replace = true } }
                    },
                    create_run_task(),
                },
            },
        })
        task:start()
    end, {})

    vim.api.nvim_create_user_command("CMakeRun", function()
        local task = create_run_task()
        if task then
            overseer.new_task(task):start()
        end
    end, {})

    vim.api.nvim_create_user_command("CMakeCancel", function()
        -- Get the list of all tasks
        local all_tasks = overseer.list_tasks()
        -- Find the task you want to stop, for example by name or other property
        for _, task in ipairs(all_tasks) do
            task:stop()
        end
    end, {})

    vim.api.nvim_create_user_command("CMakeTargetRunConfig", function()
        if _config.current_target == nil then
            print("No cmake target selected. Use CMakeSelectTarget first")
            return
        end

        local file = get_target_config_file(_config.current_target.name)
        if not file:exists() then
            file:touch({ parents = true })
            file:write(target_run_default_config, 'w')
        end
        vim.api.nvim_command('edit ' .. file.filename)
    end, {})

    vim.api.nvim_create_user_command("CMakeSelectTarget", function()
        local all_targets = cmake.get_all_executable_targets(_config.build_dir)
        local all_targets_names = {}
        for _, t in ipairs(all_targets) do
            table.insert(all_targets_names, t.name)
        end

        require('telescope.pickers').new({}, {
            prompt_title = 'Select a String',
            finder = require('telescope.finders').new_table {
                results = all_targets_names,
            },
            sorter = require('telescope.config').values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _)
                local actions = require('telescope.actions')
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selected = require('telescope.actions.state').get_selected_entry()
                    if selected then
                        _config.current_target = all_targets[selected.index]
                        store_current_target(_config.current_target)
                    end
                end)
                return true
            end,
        }):find()
    end, {})
end

return M
