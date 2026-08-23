-- .luacheckrc — Luacheck configuration for TriuneAutocombat
-- Runs on CI via `luacheck mq2triune/` to catch typos, unused vars, shadowed
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
files["mq2triune/config/triune_data.lua"] = {
    -- Generated file; suppress all warnings
    ignore = { "" },
}

files["mq2triune/lua/kissedit/*"] = {
    -- Legacy code with different conventions
    ignore = { "211", "212", "213" },  -- unused variable/value/loop-variable
}

-- Common suppressions for the MQ pcall-guard pattern and ImGui usage
ignore = {
    "212/_%w*",      -- unused loop variable starting with _
    "431",           -- shadowing upvalue (very common with pcall patterns)
}
