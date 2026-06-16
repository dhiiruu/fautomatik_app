@echo off
REM Compile all GLSL compute shaders to SPIR-V and generate C header files
REM Requires: glslangValidator (from Vulkan SDK) and xxd (or a simple bin2c)
REM
REM Install Vulkan SDK: https://vulkan.lunarg.com/
REM Then ensure glslangValidator is in your PATH.

setlocal enabledelayedexpansion

set SRC_DIR=android\app\src\main\cpp\shaders
set OUT_DIR=%SRC_DIR%\spv

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo Compiling GLSL shaders to SPIR-V...

for %%f in (%SRC_DIR%\*.comp) do (
    set BASENAME=%%~nf
    echo   %%f -^> %OUT_DIR%\!BASENAME!.spv
    glslangValidator -V %%f -o "%OUT_DIR%\!BASENAME!.spv"
    if !ERRORLEVEL! neq 0 (
        echo   ERROR: Failed to compile %%f
        exit /b 1
    )
)

echo Generating C header files...

for %%f in (%OUT_DIR%\*.spv) do (
    set BASENAME=%%~nf
    python tools\bin2c.py %%f "%OUT_DIR%\!BASENAME!.h" !BASENAME!
)

echo Done. Compiled ^&[count] shaders.
