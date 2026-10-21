
Add-Type @'
using System;
using System.Runtime.InteropServices;

public class DdcMonitor
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    [DllImport( "user32.dll" )]
    public static extern bool EnumDisplayMonitors( IntPtr hdc, IntPtr clip, MonitorEnumProc callback, IntPtr data );

    public delegate bool MonitorEnumProc( IntPtr hMonitor, IntPtr hdc, IntPtr rect, IntPtr data );

    [DllImport( "dxva2.dll", SetLastError = true)]
    public static extern bool GetPhysicalMonitorsFromHMONITOR( IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors );

    [DllImport( "dxva2.dll", SetLastError = true )]
    public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR( IntPtr hMonitor, out uint count );

    [DllImport( "dxva2.dll", SetLastError = true )]
    public static extern bool GetMonitorBrightness( IntPtr hMonitor, out uint min, out uint current, out uint max );

    [DllImport( "dxva2.dll", SetLastError = true )]
    public static extern bool SetMonitorBrightness( IntPtr hMonitor, uint newBrightness );

    [DllImport( "dxva2.dll" )]
    public static extern bool DestroyPhysicalMonitor( IntPtr hMonitor );

    private PHYSICAL_MONITOR[] pm_monitors = new PHYSICAL_MONITOR[0];

    public uint UpdateMonitors()
    {
        uint cnt = 0;
        EnumDisplayMonitors( IntPtr.Zero, IntPtr.Zero, ( hMonitor, hdc, rect, data ) => {
            if( ! GetNumberOfPhysicalMonitorsFromHMONITOR( hMonitor, out cnt ) || cnt == 0 )
                return true;
            
            pm_monitors = new PHYSICAL_MONITOR[cnt];
            if( ! GetPhysicalMonitorsFromHMONITOR( hMonitor, cnt, pm_monitors ) )
                return true;
            
            return true;
        }, IntPtr.Zero );
        return cnt;
    }

    public void DestroyMonitors()
    {
        foreach( var m in pm_monitors ){
            if( m.hPhysicalMonitor != IntPtr.Zero ){
                DestroyPhysicalMonitor( m.hPhysicalMonitor );
            }
        }
        pm_monitors = new PHYSICAL_MONITOR[0];
    }

    public int SetBrightness( uint target )
    {
        int rv = 0;

        if( pm_monitors.Length > 0 ){
            foreach( var m in pm_monitors ){
                uint min, cur, max;
                if( ! GetMonitorBrightness( m.hPhysicalMonitor, out min, out cur, out max) )
                    continue;

                if( target < min || target > max ){
                    rv |= 0x00000001;
                    continue;
                }

                if( ! SetMonitorBrightness( m.hPhysicalMonitor, target ) ){
                    rv |= 0x00000002;
                    //Marshal.GetLastWin32Error()
                }
            }
        }
        return rv;
    }
}
'@

$ddc = [DdcMonitor]::new();
$bright_prev = -1

$ddc.UpdateMonitors() | Out-Null

try{
    while( 1 ){
        try {
            $monitor = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness | `
                Where-Object { $_.Active } | Select-Object -First 1

            if( $null -ne $monitor ){
                $bright_cur = [int]$monitor.CurrentBrightness
                if( $bright_cur -ne $bright_prev ){
                    $bright_new  = [uint][Math]::Floor( $bright_cur / 2 )
                    $result      = $ddc.SetBrightness( $bright_new )

                    Write-Host "$(Get-Date -Format 'HH:mm:ss') $result Main=$bright_cur Ext=$bright_new"

                    if( $result -ne 0 ){
                        $ddc.DestroyMonitors()
                        $ddc.UpdateMonitors() | Out-Null
                    } else{
                        $bright_prev = $bright_cur
                    }
                }
            }
        } catch {
            Write-Warning $_
        }
        Start-Sleep -Seconds 2
    }
} finally{
    $ddc.DestroyMonitors()
}
