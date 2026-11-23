@echo off
cd /d "%~dp0"
docker compose stop
echo Servicios detenidos. Los datos se conservan en el volumen canariapp_canariapp_pg.
pause
