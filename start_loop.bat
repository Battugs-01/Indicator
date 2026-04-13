@echo off
REM Background loop launcher for 2-agent Forex Bot improvement
REM Usage: start_loop.bat [max_cycles]

cd /d C:\Users\Administrator\indicator
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1

if "%1"=="" (
    set CYCLES=30
) else (
    set CYCLES=%1
)

start "FractalBotLoop" /B python -u agents\run_agents.py ^
    --max-cycles %CYCLES% ^
    --target-winrate 35 ^
    --min-winrate 35 ^
    --test-months 1 ^
    --mode tbm ^
    > agents\workspace\loop.log 2>&1

echo Loop started in background. Log: agents\workspace\loop.log
