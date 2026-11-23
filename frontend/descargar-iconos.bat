@echo off
REM Descarga los iconos del Figma a public\img (los links expiran el 28-11-2026)
cd /d "%~dp0public\img"
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/f6444.svg" -o logo.svg
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/7e864.svg" -o flecha.svg
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/00a99.svg" -o ic-parejas.svg
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/e85f7.svg" -o ic-crias.svg
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/5db6e.svg" -o ic-genealogia.svg
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/2edb3.svg" -o ic-titulos.svg
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/57812.svg" -o ic-simulador.svg
curl -sL "https://www.figma.com/api/mcp/asset/1cdc782d-be6a-4ce1-8f84-1ad9748c96fb/cc89a.svg" -o ic-canarios.svg
curl -sL "https://www.figma.com/api/mcp/asset/5f3e39ab-e14f-46de-a6c0-6fa14edb605d/02113.svg" -o ojo.svg
curl -sL "https://www.figma.com/api/mcp/asset/6bfbb0cc-d8ce-4d9a-b04b-f922f1719d7b/5b186.svg" -o bandera.svg
curl -sL "https://www.figma.com/api/mcp/asset/6bfbb0cc-d8ce-4d9a-b04b-f922f1719d7b/2a408.svg" -o mas.svg
curl -sL "https://www.figma.com/api/mcp/asset/6bfbb0cc-d8ce-4d9a-b04b-f922f1719d7b/9db97.svg" -o buscar.svg
curl -sL "https://www.figma.com/api/mcp/asset/6bfbb0cc-d8ce-4d9a-b04b-f922f1719d7b/2df86.svg" -o chevron.svg
curl -sL "https://www.figma.com/api/mcp/asset/e0a38f8a-416e-489e-b090-db42c383b642/c66a7.svg" -o corazon.svg
curl -sL "https://www.figma.com/api/mcp/asset/0d6bd84e-6196-4984-bc8c-669165abd6a5/28197.svg" -o huevo.svg
curl -sL "https://www.figma.com/api/mcp/asset/0d6bd84e-6196-4984-bc8c-669165abd6a5/d8375.svg" -o flecha-der.svg
curl -sL "https://www.figma.com/api/mcp/asset/b4bc8b23-7960-4164-b587-656df0b8aea8/7087b.svg" -o trofeo.svg
echo Listo. Iconos descargados en public\img
pause
