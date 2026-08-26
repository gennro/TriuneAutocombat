-- .luacheckrc — Luacheck configuration for TriuneAutocombat
-- Runs on CI via `luacheck TAC/` to catch typos, unused vars, shadowed
-- locals, and references to undefined globals.

std = "luajit"

-- Maximum line length (disabled — some UI lines are naturally long)
max_line_length = false

-- MacroQuest / ImGui globals that MQ injects at runtime
globals = {
    "mq",
    "ImGui",
    "ImGuiCond",
    "ImGuiCol",
    "ImGuiStyleVar",
    "ImGuiTableFlags",
    "ImGuiTableColumnFlags",
    "ImGuiSelectableFlags",
    "ImGuiWindowFlags",
    "ImGuiTreeNodeFlags",
    "ImGuiTabBarFlags",
    "ImGuiTabItemFlags",
    "ImGuiMod",
    "ImGuiKey",
    "ImVec2",
    "ImVec4",
    "IM_COL32",
    "bit",
    "DATA",
}

-- Read-only globals (can be read but not assigned)
read_globals = {
    "clearCursor",
    os = { fields = { "clock", "time", "date", "difftime" } },
    string = { fields = { "format", "find", "match", "gmatch", "gsub",
                          "sub", "upper", "lower", "len", "rep", "byte",
                          "char", "reverse" } },
    table  = { fields = { "insert", "remove", "sort", "concat", "maxn" } },
    math   = { fields = { "floor", "ceil", "abs", "min", "max", "sqrt",
                          "huge", "random", "randomseed", "pi", "fmod",
                          "sin", "cos", "atan2" } },
    io     = { fields = { "open", "read", "write", "close" } },
}

-- Per-file overrides
files["TAC/config/triune_data.lua"] = {
    -- Generated file; suppress all warnings
    ignore = { "" },
}

files["TAC/lua/kissedit/*"] = {
    -- Legacy code with different conventions
    ignore = { "" },
}
files["TAC/lua/kissedit/**/*"] = {
    ignore = { "" },
}

files["TAC/lua/triune.lua"] = {
    -- classPlausible is tested by test_pure_logic.lua test suite
    ignore = { "211/classPlausible" },
}

files["TAC/lua/triune_buttons.lua"] = {
    -- Standalone duplicated color palette constants
    ignore = { "211/GOOD", "211/WARN", "211/ERR", "211/MUTED" },
}

files["TAC/lua/triune_buffbot.lua"] = {
    -- Standalone duplicated ImGui theme popCol helper
    ignore = { "211/popCol" },
}

-- Common suppressions for the MQ pcall-guard pattern, ImGui callbacks, and formatting
ignore = {
    "611",           -- line contains only whitespace
    "612",           -- line contains trailing whitespace
    "613",           -- trailing whitespace inside string
    "621",           -- inconsistent indentation
    "212",           -- unused argument (event handlers, ImGui callbacks)
    "212/_%w*",      -- unused loop variable starting with _
    "431",           -- shadowing upvalue (very common with pcall patterns)
    "432",           -- shadowing upvalue argument
}
