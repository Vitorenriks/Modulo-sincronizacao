@echo off
rem Diagnostico-corrigir.cmd - o mesmo diagnostico, mas com permissao para
rem desbloquear o .exe que o Windows marcou como "vindo da internet".
rem
rem Esta separado do Diagnostico.cmd de proposito: o diagnostico normal nao
rem muda nada, para que a causa apareca no relatorio em vez de ser apagada
rem sem ninguem ver. Quem clica aqui esta autorizando a correcao.
setlocal
title Diagnostico da ferramenta (corrigindo)
echo.
echo  Verificando esta maquina e desbloqueando o programa, se preciso...
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnostico.ps1" -Corrigir
echo.
echo  Pressione qualquer tecla para fechar.
pause >nul
