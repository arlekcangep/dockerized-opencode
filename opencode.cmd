@echo off
setlocal EnableExtensions

rem =====================================================================
rem  run-opencode.cmd  (single-ssh version)
rem
rem  Hot path: exactly ONE ssh call, no probes, no vagrant.
rem
rem  How it works:
rem    ssh -t vagrant "docker exec -it opencode opencode; <recovery>"
rem
rem    The recovery part runs INSIDE the same ssh session:
rem      - if opencode exited normally (rc=0)          -> exit 0
rem      - if the container is still running (rc!=0)   -> exit rc (real app error)
rem      - if the container is NOT running             -> docker compose up -d --build,
rem                                                       then exec opencode again
rem
rem  If ssh itself cannot connect (VM is down, exit code 255):
rem      vagrant up -> wait for ssh -> retry once
rem
rem  Usage:  run-opencode.cmd [opencode arguments]
rem =====================================================================

set "VAGRANT_DIR=D:\home\projects\vagrant"

rem --- ssh settings -----------------------------------------------------
rem  SSH_HOST is the alias from %USERPROFILE%\.ssh\config
set "SSH_HOST=vagrant"
set "SSH_OPTS=-o BatchMode=yes -o ConnectTimeout=3 -o ConnectionAttempts=1"

set "CONTAINER=opencode"
set "COMPOSE_DIR=~/shared/opencode"
set "WAIT_SSH_TRIES=40"

set "RC=0"
set "FAILED="

call :log "opencode launcher"

where ssh >nul 2>&1
if errorlevel 1 (
    call :err "ssh.exe was not found in PATH"
    goto :fail
)

rem ---------------------------------------------------------------------
rem  1. Fast path: one ssh call, recovery inside the remote shell
rem ---------------------------------------------------------------------
call :run_opencode
if not "%RC%"=="255" goto :done

rem ---------------------------------------------------------------------
rem  2. ssh could not connect at all -> VM is probably down
rem ---------------------------------------------------------------------
call :log "SSH connection failed (exit 255) - VM is probably down"

where vagrant >nul 2>&1
if errorlevel 1 (
    call :err "vagrant.exe was not found in PATH and VM is not reachable"
    goto :fail
)
if not exist "%VAGRANT_DIR%\" (
    call :err "Vagrant directory not found: %VAGRANT_DIR%"
    goto :fail
)

pushd "%VAGRANT_DIR%" >nul 2>&1
if errorlevel 1 (
    call :err "Cannot enter directory: %VAGRANT_DIR%"
    goto :fail
)
call :log "Running 'vagrant up'..."
vagrant up
set "UP_RC=%errorlevel%"
popd
if not "%UP_RC%"=="0" (
    call :err "'vagrant up' failed (exit %UP_RC%)"
    goto :fail
)

call :wait_ssh
if errorlevel 1 (
    call :err "SSH to '%SSH_HOST%' did not come up in time"
    call :err "Check manually: ssh %SSH_OPTS% %SSH_HOST% true"
    goto :fail
)

call :log "Retrying..."
call :run_opencode
if "%RC%"=="255" (
    call :err "Still cannot connect to '%SSH_HOST%'"
    goto :fail
)
goto :done

rem =====================================================================
rem  Helpers
rem =====================================================================
:run_opencode
ssh -t %SSH_HOST% "docker exec -it %CONTAINER% opencode %*; rc=$?; if [ $rc -eq 0 ]; then exit 0; fi; st=`docker inspect -f '{{.State.Running}}' %CONTAINER% 2>/dev/null`; if [ x$st = xtrue ]; then exit $rc; fi; echo [launcher] container %CONTAINER% is not running - starting it...; cd %COMPOSE_DIR% || exit 1; docker compose up -d --build || docker-compose up -d --build || exit 1; docker exec -it %CONTAINER% opencode %*"
set "RC=%errorlevel%"
call :log "opencode exited with code %RC%"
exit /b 0

:wait_ssh
set /a tries=0
:wait_ssh_loop
ssh %SSH_OPTS% %SSH_HOST% "true" >nul 2>&1
if not errorlevel 1 exit /b 0
set /a tries+=1
if %tries% geq %WAIT_SSH_TRIES% exit /b 1
ping -n 2 127.0.0.1 >nul
goto :wait_ssh_loop

:log
echo [%TIME:~0,8%] %~1
exit /b 0

:err
echo [%TIME:~0,8%] ERROR: %~1 1>&2
exit /b 0

rem =====================================================================
rem  Exit
rem =====================================================================
:fail
set "RC=1"
set "FAILED=1"

:done
if defined FAILED (
    echo.
    echo Script failed, exit code %RC%.
    pause
)
endlocal & exit /b %RC%
