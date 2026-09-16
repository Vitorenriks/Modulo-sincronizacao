@echo off
rem Diagnostico.cmd - o que a pessoa clica.
rem
rem Existe por um motivo so: em maquina nenhuma da empresa da para contar que
rem um .ps1 abra com dois cliques. A politica de execucao do PowerShell barra,
rem ou o duplo clique abre o script no Notepad. Um .cmd sempre roda.
rem
rem Sem acento neste arquivo: .cmd e lido na pagina de codigo do console, e
rem acento aqui viraria lixo na tela.
setlocal
title Diagnostico da ferramenta
echo.
echo  Verificando esta maquina. Leva alguns segundos...
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnostico.ps1"
echo.
echo  Pressione qualquer tecla para fechar.
pause >nul
