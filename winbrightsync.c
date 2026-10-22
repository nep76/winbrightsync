// PowerShellスクリプトをウィンドウ無しで起動する方法がよくわからないので
// 一時しのぎで強引に起動
//
// winbrightsync.exeとwinbrightsync.ps1を
// 同じディレクトリにおいて、作業ディレクトリを同ディレクトリ設定

#include <windows.h>

int WINAPI wWinMain( HINSTANCE hInstance, HINSTANCE hPrevInstance, PWSTR pCmdLine, int nCmdShow )
{
    STARTUPINFOW        si = { sizeof( si ) };
    PROCESS_INFORMATION pi = { 0 };

    WCHAR cmd[] = L"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \".\\winbrightsync.ps1\" sync";

    if( CreateProcessW( NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi ) ){
        CloseHandle( pi.hThread );
        CloseHandle( pi.hProcess );
    }

    return 0;
}