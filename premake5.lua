require "vstudio"

newoption {
   trigger = "no-shared-release-deps",
   description = "Compile common native Release dependencies separately for each plugin"
}

-- PS2 and PSP as Visual Studio platforms of their own (as premake-consoles does for
-- consoles); their projects are Makefile ones, so no MSBuild platform files are needed.
premake.vstudio.vs2010_architectures.ps2 = "PS2"
premake.vstudio.vs2010_architectures.psp = "PSP"
premake.api.addAllowed("system", { "ps2", "psp" })

-- The folder a project is deployed to, and the game it is started from when debugging,
-- is the path of one machine and does not belong in the repository. It is read from a
-- `.env` file next to this script, which is not tracked by git and holds one
-- `<KEY>=<folder>` line per game (quotes and a trailing slash are optional). A project
-- whose key is missing is not deployed at all.
local envkeys = nil
function envdir(key)
   if not envkeys then
      envkeys = {}
      local text = io.readfile(path.join(_SCRIPT_DIR, ".env")) or ""
      for line in text:gmatch("[^\r\n]+") do
         local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
         if k and v ~= "" then
            v = v:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
            envkeys[k] = v
         end
      end
   end

   local value = envkeys[key]
   if not value then return nil end

   value = value:gsub("[%s\\/]+$", "")
   if value == "" then return nil end

   return path.translate(value)
end

-- Deploys the built .asi into the script folder of the game that `key` names in the .env
-- file, and starts the game from there when debugging. Only a plugin that is already
-- installed in the game folder is replaced, a folder without one is left alone.
function setpaths(key, exepath, scriptspath)
   scriptspath = scriptspath or "scripts/"
   local gamepath = envdir(key)
   if gamepath then
      local target = gamepath .. "\\" .. path.translate(scriptspath)
      postbuildcommands {
         "if exist \"" .. target .. "$(TargetFileName)\" copy /y \"$(TargetPath)\" \"" .. target .. "\"",
      }
      debugdir (gamepath)
      if (exepath) then
         debugcommand (gamepath .. "\\" .. path.translate(exepath))
         local dir = exepath:match'(.*/)(.*)'
         debugdir (gamepath .. "\\" .. path.translate(dir or ""))
      end
   end
   targetdir ("data/%{prj.name}/" .. scriptspath)
end

function setbuildpaths_psp(key, exepath, scriptspath, pspsdkpath, sourcepath, prj_name)
   local command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "%{wks.location}/../external/pspsdk/plugins/build-module.ps1" -Project "' .. sourcepath .. 'module.json" -Configuration "%{cfg.buildcfg}"'
   local gamepath = envdir(key)
   local deploy = {}
   if gamepath then
      local target = path.join(gamepath, "memstick/PSP/PLUGINS/", prj_name)
      deploy = { 'if not exist "' .. target .. '" mkdir "' .. target .. '"',
         'copy /y "$(NMakeOutput)" "' .. target .. '"' }
      debugdir(gamepath)
      debugcommand(path.join(gamepath, exepath))
   end
   buildcommands { command, 'if errorlevel 1 exit /b %errorlevel%', deploy }
   rebuildcommands { command .. ' -Clean', 'if errorlevel 1 exit /b %errorlevel%', command,
      'if errorlevel 1 exit /b %errorlevel%', deploy }
   cleancommands { command .. ' -Clean' }
   targetdir("data/%{prj.name}/" .. scriptspath)
end

function setbuildpaths_ps2(key, exepath, scriptspath, ps2sdkpath, sourcepath, prj_name)
   local command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "%{wks.location}/../external/ps2sdk/plugins/build-module.ps1" -Project "' .. sourcepath .. 'module.json"'
   local gamepath = envdir(key)
   local deploy = {}
   if gamepath then
      local target = path.join(gamepath, scriptspath)
      deploy = { 'if not exist "' .. target .. '" mkdir "' .. target .. '"',
         'copy /y "$(NMakeOutput)" "' .. target .. '"' }
      debugdir(gamepath)
      debugcommand(path.join(gamepath, os.isfile(path.join(gamepath, "pcsx2-qtx64.exe")) and "pcsx2-qtx64.exe" or "pcsx2-qt.exe"))
   end
   buildcommands { command, 'if errorlevel 1 exit /b %errorlevel%', deploy }
   rebuildcommands { command .. ' -Clean', 'if errorlevel 1 exit /b %errorlevel%', command,
      'if errorlevel 1 exit /b %errorlevel%', deploy }
   cleancommands { command .. ' -Clean' }
   targetdir("data/%{prj.name}/" .. scriptspath)
end

function add_kananlib()
   defines { "BDDISASM_HAS_MEMSET", "BDDISASM_HAS_VSNPRINTF" }
   files { "external/injector/kananlib/include/utility/**.hpp", "external/injector/kananlib/src/**.cpp" }
   files { "external/injector/bddisasm/bddisasm/*.c" }
   files { "external/injector/bddisasm/bdshemu/*.c" }
   includedirs { "external/injector/kananlib/include" }
   includedirs { "external/injector/bddisasm/inc" }
   includedirs { "external/injector/bddisasm/bddisasm/include" }
end

-- Compiles shaders with the DirectX SDK tools shipped in tools/x86, one custom build step per file. Same idea
-- as Visual Studio's FxCompile build action, but with the June 2010 compiler, which is the one that still
-- handles the D3D9 era profiles (fx_2_0, ps_1_1 with /LD, ...). Unlike a prebuild command this only runs when
-- a shader actually changed, and the output is tracked by MSBuild.
-- Both the input and the output are passed as paths relative to the project file, as written in the project
-- and with the output next to the shader, where the .rc files expect it. Do not use %(FullPath)/%(Directory)
-- here: they expand to a drive-stripped absolute path, which makes the June 2010 compiler write the output to
-- a bogus "build/<source tree>" mirror and fails there on some machines (AppVeyor) instead of compiling.
-- Rules: { files = <file pattern>, ext = <output extension>, tool = "fxc" (default) | "asm_shader",
--          args = <tool arguments>, out = <optional output path, defaults to a sibling of the source> }
-- `args` and `out` may use the input file's metadata, written with a single % (e.g. %(Filename)).
function buildshaders(rules)
   for _, rule in ipairs(rules) do
      local tool = rule.tool or "fxc"
      local exe = "../tools/x86/" .. tool .. ".exe"
      local input = "%(RelativeDir)%(Filename)%(Extension)"
      local out = rule.out or ("%(RelativeDir)%(Filename)" .. (rule.ext or ".fxo"))
      local command
      if tool == "asm_shader" then
         command = string.format('"%s" "%s" "%s"', exe, input, out)
      else
         command = string.format('"%s" %s /Fo "%s" "%s"', exe, rule.args or "", out, input)
      end
      filter { "files:" .. rule.files }
         buildaction "CustomBuild"
         buildmessage("Compiling %(Filename)%(Extension) with " .. tool)
         buildcommands { command }
         buildoutputs { out }
      filter {}
   end
end

function add_postfx(id_postfx, id_areatex, id_searchtex)
   id_postfx = id_postfx or 201
   id_areatex = id_areatex or id_postfx + 1
   id_searchtex = id_searchtex or id_postfx + 2
   buildshaders {
      { files = "includes/postfx/*.fx", args = "/T fx_2_0", ext = ".fxo" }
   }
   includedirs { "Resources", "includes/postfx" }
   files { "includes/postfx/postfxcore.ixx", "includes/postfx/postfx.fx", "includes/postfx/postfx.fxo", "includes/postfx/postfx.rc" }
   defines { "IDR_POSTFX=" .. id_postfx }
   defines { "IDR_AREATEX=" .. id_areatex }
   defines { "IDR_SEARCHTEX=" .. id_searchtex }
end

function add_pspsdk()
   includedirs { "external/pspsdk/usr/local/pspdev/psp/sdk/include" }
   includedirs { "external/pspsdk/usr/local/pspdev/bin" }
   files { "source/%{prj.name}/*.h", "source/%{prj.name}/*.hpp", "source/%{prj.name}/*.c", "source/%{prj.name}/*.cpp", "source/%{prj.name}/makefile", "source/%{prj.name}/module.json", "source/%{prj.name}/exports.exp" }
end

function add_ps2sdk()
   includedirs { "external/ps2sdk/ps2sdk/ee" }
   files { "source/%{prj.name}/*.h", "source/%{prj.name}/*.hpp", "source/%{prj.name}/*.c", "source/%{prj.name}/*.cpp", "source/%{prj.name}/makefile", "source/%{prj.name}/module.json" }
end

function writeghaction(tag, prj_name)
   file = io.open(".github/workflows/" .. tag .. ".yml", "w")
   if (file) then
str = [[
name: %s

on:
  workflow_dispatch:

jobs:
  call-workflow-passing-data:
    uses: ThirteenAG/WidescreenFixesPack/.github/workflows/all.yml@master
    with:
      tag_list: %s
      project: /t:%s
]]
      file:write(string.format(str, tag, tag, prj_name:gsub("%.", "_")))
      file:close()
   end
end

function CommonWorkspaceSetup(platform, prefix)
   workspace (prefix .. ".WidescreenFixesPack")
      configurations { "Release", "Debug" }
      platforms { platform }
      location "build"
      objdir ("build/obj")
      buildlog ("build/log/%{prj.name}.log")
      cppdialect "C++latest"
      include "makefile.lua"
      buildoptions { "/Zc:__cplusplus /utf-8" }
      multiprocessorcompile ("On")

      kind "SharedLib"
      language "C++"
      targetdir "data/%{prj.name}/scripts"
      targetextension ".asi"
      characterset ("UNICODE")
      staticruntime "On"

      defines { "rsc_CompanyName=\"ThirteenAG\"" }
      defines { "rsc_LegalCopyright=\"MIT License\""}
      defines { "rsc_InternalName=\"%{prj.name}\"", "rsc_ProductName=\"%{prj.name}\"", "rsc_OriginalFilename=\"%{cfg.buildtarget.name}\"" }
      defines { "rsc_FileDescription=\"https://thirteenag.github.io/wfp\"" }
      defines { "rsc_UpdateUrl=\"https://github.com/ThirteenAG/WidescreenFixesPack\"" }

      local major = os.date("%d")
      local minor = os.date("%m")
      local build = os.date("%Y")
      local revision = os.date("%H") .. os.date("%M")

      local githash = ""
      local f = io.popen("git rev-parse --short HEAD")
      if f then
         githash = f:read("*a"):gsub("%s+", "")
         f:close()
      end

      local productVersion = major .. "." .. minor .. "." .. build .. "." .. revision
      if githash ~= "" then
         productVersion = productVersion .. "-" .. githash
      end

      defines { "rsc_FileVersion_MAJOR=" .. major }
      defines { "rsc_FileVersion_MINOR=" .. minor }
      defines { "rsc_FileVersion_BUILD=" .. build }
      defines { "rsc_FileVersion_REVISION=" .. revision }
      defines { "rsc_FileVersion=\"" .. major .. "." .. minor .. "." .. build .. "\"" }
      defines { "rsc_ProductVersion=\"" .. productVersion .. "\"" }
      defines { "rsc_GitSHA1=\"" .. githash .. "\"" }
      defines { "rsc_GitSHA1W=L\"" .. githash .. "\"" }

      files { "source/%{prj.name}/*.h", "source/%{prj.name}/*.cpp", "source/%{prj.name}/*.hxx", "source/%{prj.name}/*.ixx" }
      files { "data/%{prj.name}/**" }
      files { "Resources/*.rc" }
      files { "external/hooking/Hooking.Patterns.h", "external/hooking/Hooking.Patterns.cpp" }
      files { "external/injector/safetyhook/include/**.hpp", "external/injector/safetyhook/src/**.cpp" }
      files { "external/injector/minhook/include/*.h", "external/injector/minhook/src/**.h", "external/injector/minhook/src/**.c" }
      files { "external/injector/utility/FunctionHookMinHook.hpp", "external/injector/utility/FunctionHookMinHook.cpp" }
      files { "external/injector/zydis/**.h", "external/injector/zydis/**.c" }
      files { "includes/stdafx.h", "includes/stdafx.cpp" }
      includedirs { "external/injector/minhook/include" }
      includedirs { "external/injector/utility" }
      includedirs { "external/injector/safetyhook/include" }
      includedirs { "external/injector/zydis" }
      includedirs { "external/hooking" }
      includedirs { "external/injector/include" }
      includedirs { "external/inireader" }
      includedirs { "external/spdlog/include" }
      includedirs { "external/filewatch" }
      includedirs { "external/modutils" }
      includedirs { "includes" }

      includedirs { "includes/LED" }
      libdirs { "includes/LED" }

      includedirs { "external/minidx9/Include" }

      vpaths {
         ["source"] = { "source/**.*" },
         ["shaders"] = { "source/**.fx", "source/**.vs", "source/**.ps", "source/**.hlsl" },
         ["ini"] = { "data/**.ini" },
         ["data"] = { "data/**.cfg", "data/**.dat" },
         ["resources/*"] = { "resources/*" },
         ["includes/*"] = { "includes/**" },
         ["external/*"] = { "external/**" },
      }

      filter { "platforms:Win32" }
         architecture "x86"
         libdirs { "external/minidx9/Lib/x86" }
      filter { "platforms:x64" }
         architecture "x64"
         libdirs { "external/minidx9/Lib/x64" }
      -- unknown VS platforms: keep the system PATH for the build commands
      filter { "platforms:PS2" }
         system "ps2"
         bindirs { "$(PATH)" }
      filter { "platforms:PSP" }
         system "psp"
         bindirs { "$(PATH)" }
      filter {}

      filter "configurations:Debug*"
         defines "DEBUG"
         symbols "On"

      filter "configurations:Release*"
         defines "NDEBUG"
         optimize "On"
end

-- ====================== WIN32 SOLUTION ======================
CommonWorkspaceSetup("Win32", "Win32")

group "NeedForSpeed"
project "NFSTheRun.FusionFix"
   setpaths("NEED_FOR_SPEED_THE_RUN_DIR", "Need For Speed The Run.exe", "plugins/")
project "NFSCarbon.WidescreenFix"
   add_postfx()
   setpaths("NEED_FOR_SPEED_CARBON_DIR", "NFSC.exe")
project "NFSMostWanted.WidescreenFix"
   buildshaders {
      { files = "source/*/*.fx", args = "/T fx_2_0", ext = ".fxo" }
   }
   includedirs { "Resources", "includes/postfx" }
   files { "includes/postfx/postfxcore.ixx", "source/%{prj.name}/*.fx", "source/%{prj.name}/*.rc" }
   defines { "IDR_POSTFX=201" }
   defines { "IDR_AREATEX=202" }
   defines { "IDR_SEARCHTEX=203" }
   setpaths("NEED_FOR_SPEED_MOST_WANTED_DIR", "speed.exe")
project "NFSProStreet.FusionFix"
   add_postfx()
   setpaths("NEED_FOR_SPEED_PROSTREET_DIR", "nfsps.exe")
project "NFSUndercover.FusionFix"
   add_postfx()
   setpaths("NEED_FOR_SPEED_UNDERCOVER_DIR", "nfs.exe")
project "NFSUnderground.WidescreenFix"
   add_postfx()
   defines { "IDR_NFSUICON=200" }
   files { "textures/NFS/NFSU/icon.rc" }
   setpaths("NEED_FOR_SPEED_UNDERGROUND_DIR", "speed.exe")
project "NFSUnderground2.WidescreenFix"
   add_postfx()
   setpaths("NEED_FOR_SPEED_UNDERGROUND_2_DIR", "speed2.exe")
group ""

if not _OPTIONS["no-shared-release-deps"] then
   include "tools/msbuild/shared-dependencies.lua"
end
