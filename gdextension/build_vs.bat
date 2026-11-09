@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
cd /d D:\Projects\Engine Builder\gdextension
"C:\Users\Yves Caesario\AppData\Local\Programs\Python\Python312\python.exe" -m SCons platform=windows target=template_debug