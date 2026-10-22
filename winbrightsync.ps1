Param(
    [string]$Command,
    [string]$Display,
    [int]$Brightness
)

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class DdcMonitor
{
    [StructLayout( LayoutKind.Sequential, CharSet = CharSet.Auto )]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;

        [MarshalAs( UnmanagedType.ByValTStr, SizeConst = 128 )]
        public string szPhysicalMonitorDescription;
    }

    [StructLayout( LayoutKind.Sequential, CharSet = CharSet.Auto )]
    public struct MONITORINFOEX
    {
        public uint cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;

        [MarshalAs( UnmanagedType.ByValTStr, SizeConst = 32 )]
        public string szDevice;
    }

    [StructLayout( LayoutKind.Sequential, CharSet = CharSet.Auto )]
    public struct DISPLAY_DEVICE
    {
        public uint cb;

        [MarshalAs (UnmanagedType.ByValTStr, SizeConst = 32 )]
        public string DeviceName;

        [MarshalAs( UnmanagedType.ByValTStr, SizeConst = 128 )]
        public string DeviceString;

        public uint StateFlags;

        [MarshalAs( UnmanagedType.ByValTStr, SizeConst = 128 )]
        public string DeviceID;

        [MarshalAs( UnmanagedType.ByValTStr, SizeConst = 128 )]
        public string DeviceKey;
    }

    [DllImport( "user32.dll", CharSet = CharSet.Auto )]
    public static extern bool EnumDisplayDevices( string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags );

    [StructLayout( LayoutKind.Sequential )]
    public struct RECT
    {
        public int left, top, right, bottom;
    }

    [DllImport( "user32.dll" )]
    public static extern bool EnumDisplayMonitors( IntPtr hdc, IntPtr clip, MonitorEnumProc callback, IntPtr data );

    [DllImport( "user32.dll", CharSet = CharSet.Auto )]
    public static extern bool GetMonitorInfo( IntPtr hMonitor, ref MONITORINFOEX lpmi );

    public delegate bool MonitorEnumProc( IntPtr hMonitor, IntPtr hdc, IntPtr rect, IntPtr data );

    [DllImport( "dxva2.dll", SetLastError = true )]
    public static extern bool GetPhysicalMonitorsFromHMONITOR( IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors );

    [DllImport( "dxva2.dll", SetLastError = true )]
    public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR( IntPtr hMonitor, out uint count );

    [DllImport( "dxva2.dll", SetLastError = true )]
    public static extern bool GetMonitorBrightness( IntPtr hMonitor, out uint min, out uint current, out uint max );

    [DllImport( "dxva2.dll", SetLastError = true )]
    public static extern bool SetMonitorBrightness( IntPtr hMonitor, uint newBrightness );

    [DllImport( "dxva2.dll" )]
    public static extern bool DestroyPhysicalMonitor( IntPtr hMonitor );

    public const int DDC_MONITOR_ERR_UPDATE_NEXTCYCLE = 0x01000000;

    public const int DDC_MONITOR_ERR_NOT_SUPPORTED    = 0x00000001;
    public const int DDC_MONITOR_ERR_DEVICE_NOT_FOUND = 0x00010000;
    public const int DDC_MONITOR_ERR_INVALID_PARAMS   = 0x00020000;

    public const int DDC_MONITOR_FLG_NO_DDC           = 0x00000001;
    public const int DDC_MONITOR_FLG_NO_WMI           = 0x00000002;

    public struct DdcMonitorPhysicalMonitor
    {
        public PHYSICAL_MONITOR Ctx;
        public uint BrightnessMin;
        public uint BrightnessCur;
        public uint BrightnessMax;
    }

    public class DdcMonitorInfo
    {
        public DdcMonitorPhysicalMonitor[] PhysicalMonitor;
        public string Name;
        public string DeviceId;
        public int    Flags;
    }

    private Dictionary<string, DdcMonitorInfo> pm_monitors = new();

    private void _destroy_monitors( Dictionary<string, DdcMonitorInfo> mons )
    {
        foreach( var mi_v in mons.Values ){
            foreach( var m in mi_v.PhysicalMonitor ){
                if( m.Ctx.hPhysicalMonitor != IntPtr.Zero ){
                    DestroyPhysicalMonitor( m.Ctx.hPhysicalMonitor );
                }
            }
        }
    }

    public string[] GetNames()
    {
        var ls = new string[pm_monitors.Count];
        var i = 0;

        foreach( var key in pm_monitors.Keys ){
            ls[i++] = pm_monitors[key].Name;
        }

        return ls;
    }

    public string[] GetDeviceIds()
    {
        var ls = new string[pm_monitors.Count];
        var i = 0;

        foreach( var key in pm_monitors.Keys ){
            ls[i++] = key;
        }

        return ls;
    }

    public string GetDeviceIdByName( string name )
    {
        foreach( var key in pm_monitors.Keys ){
            if( name.Equals( pm_monitors[key].Name ) ){
                return key;
            }
        }
        return "";
    }
    
    public DdcMonitorInfo GetMonitorInfo( string devid )
    {
        return pm_monitors[devid];
    }

    public uint UpdateMonitors()
    {
        Dictionary<string, DdcMonitorInfo> mils = new();
        bool update = false;

        update = EnumDisplayMonitors( IntPtr.Zero, IntPtr.Zero, ( hMonitor, hdc, rect, data ) => {
            DdcMonitorInfo mi = new();
            uint cnt;
            if( ! GetNumberOfPhysicalMonitorsFromHMONITOR( hMonitor, out cnt ) || cnt == 0 )
                return true;
            
            var ms = new PHYSICAL_MONITOR[cnt];

            if( ! GetPhysicalMonitorsFromHMONITOR( hMonitor, cnt, ms ) )
                return true;
            
            bool t_ok = false;
            try{
                var minfo = new MONITORINFOEX();
                var dinfo = new DISPLAY_DEVICE();

                minfo.cbSize = (uint)Marshal.SizeOf( typeof( MONITORINFOEX ) );
                dinfo.cb     = (uint)Marshal.SizeOf( typeof( DISPLAY_DEVICE ) );

                if( GetMonitorInfo( hMonitor, ref minfo ) ){
                    mi.Name = minfo.szDevice;

                    // 1 = EDD_GET_DEVICE_INTERFACE_NAME
                    if( EnumDisplayDevices( mi.Name, 0, ref dinfo, 1 ) ){
                        mi.DeviceId = dinfo.DeviceID;
                    }
                }

                mi.PhysicalMonitor = new DdcMonitorPhysicalMonitor[ms.Length];
                for( var i = 0; i < mi.PhysicalMonitor.Length; i++ ){
                    mi.PhysicalMonitor[i].Ctx = ms[i];
                    if( ! GetMonitorBrightness( ms[i].hPhysicalMonitor,
                                        out mi.PhysicalMonitor[i].BrightnessMin,
                                        out mi.PhysicalMonitor[i].BrightnessCur,
                                        out mi.PhysicalMonitor[i].BrightnessMax ) ){
                        mi.Flags |= DDC_MONITOR_FLG_NO_DDC;
                    }
                }

                mils.Add( mi.DeviceId, mi );

                t_ok = true;
            } finally{
                if( ! t_ok ){
                    foreach( var m in ms ){
                        DestroyPhysicalMonitor( m.hPhysicalMonitor );
                    }
                }
            }

            return true;
        }, IntPtr.Zero );

        if( update ){
            _destroy_monitors( pm_monitors );
            pm_monitors = mils;
        } else{
            _destroy_monitors( mils );
        }

        return (uint)pm_monitors.Count;
    }

    public void DestroyMonitors()
    {
        _destroy_monitors( pm_monitors );
        pm_monitors = new();
    }

    public int SetBrightness( string devid, uint target )
    {
        if( pm_monitors.ContainsKey( devid ) ){
            if( ( pm_monitors[devid].Flags & DDC_MONITOR_FLG_NO_DDC ) != 0 ){
                uint b_min, b_cur, b_max;
                int err = 0;
                for( var i = 0; i < pm_monitors[devid].PhysicalMonitor.Length; i++ ){
                    if( ! GetMonitorBrightness( pm_monitors[devid].PhysicalMonitor[i].Ctx.hPhysicalMonitor,
                                                out b_min,
                                                out b_cur,
                                                out b_max ) ){
                        err++;
                    }
                }
                if( err == 0 ){
                    pm_monitors[devid].Flags &= ~DDC_MONITOR_FLG_NO_DDC;
                    return DDC_MONITOR_ERR_UPDATE_NEXTCYCLE;
                }       
            } else{
                for( var i = 0; i < pm_monitors[devid].PhysicalMonitor.Length; i++ ){
                    if( ! GetMonitorBrightness( pm_monitors[devid].PhysicalMonitor[i].Ctx.hPhysicalMonitor,
                                                out pm_monitors[devid].PhysicalMonitor[i].BrightnessMin,
                                                out pm_monitors[devid].PhysicalMonitor[i].BrightnessCur,
                                                out pm_monitors[devid].PhysicalMonitor[i].BrightnessMax ) ){
                        return DDC_MONITOR_ERR_NOT_SUPPORTED;
                    }
                                                
                    if( target < pm_monitors[devid].PhysicalMonitor[i].BrightnessMin || 
                        target > pm_monitors[devid].PhysicalMonitor[i].BrightnessMax ){
                        return DDC_MONITOR_ERR_INVALID_PARAMS;
                    }

                    if( ! SetMonitorBrightness( pm_monitors[devid].PhysicalMonitor[i].Ctx.hPhysicalMonitor, target ) ){
                        return DDC_MONITOR_ERR_NOT_SUPPORTED;
                        //Marshal.GetLastWin32Error()
                    }
                }
            }
        } else{
            return DDC_MONITOR_ERR_DEVICE_NOT_FOUND;
        }
        return 0;
    }
}
'@

$ddc = [DdcMonitor]::new();
$bright_prev = -1

try{
    $ddc.UpdateMonitors() | Out-Null

    if( $Display -and $Display.StartsWith( "\\.\" ) ){
        $Display = $ddc.GetDeviceIdByName( $Display );
    }

    switch( $Command ){
        "info" {
            Write-Host "Display Information:"
            $names = $ddc.GetNames();
            foreach( $name in $names ){
                $devid = $ddc.GetDeviceIdByName( $name );
                if( $devid -ne "" ){
                    $mi = $ddc.GetMonitorInfo( $devid );
                    [PSCustomObject]@{
                        DeviceId = $devid
                        Name = $name
                        Brightness = $mi.PhysicalMonitor[0].BrightnessCur
                    }
                }
            }
        }
        "brightness" {
            if( $ddc.SetBrightness( $Display, $Brightness ) -ne 0 ){
                Write-Host "Failed to change the brightness"
            }
        }
        "sync" {
            $monitors = $ddc.GetDeviceIds();
            while( 1 ){
                try {
                    # $ddcがWMIとDDC/CIを透過的にあつかえるようにまだなってないから
                    # 基準ディスプレイはWMIの1個目に決め打ち
                    $main_monitor = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness | `
                        Where-Object { $_.Active } | Select-Object -First 1
                    
                    if( $null -ne $main_monitor ){
                        $bright_cur = [int]$main_monitor.CurrentBrightness
                        if( $bright_cur -ne $bright_prev ){
                            $bright_new  = [uint][Math]::Floor( $bright_cur / 2 )

                            $result = 0;
                            foreach( $devid in $monitors ){
                                $result = $result -bor $ddc.SetBrightness( $devid, $bright_new );
                            }

                            Write-Host ( "$(Get-Date -Format 'HH:mm:ss') 0x{0:X8} Main=$bright_cur Ext=$bright_new" -f $result )

                            if( $result -ne 0 ){
                                $ddc.UpdateMonitors() | Out-Null
                                $monitors = $ddc.GetDeviceIds();
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
        }
        default {
            Write-Host "Usage: $(Split-Path -Leaf $PSCommandPath) <COMMAND> [DISPLAY] [ARG]"
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "    info"
            Write-Host "        List detected monitors."
            Write-Host ""
            Write-Host "    brightness <DISPLAY> <NUM>:"
            Write-Host "        Set the brightness of the specified <DISPLAY>."
            Write-Host ""
            Write-Host "    sync <DISPLAY>:"
            Write-Host "        Synchronize other monitors with the specified <DISPLAY>'s brightness."
            Write-Host "        (Keep running)"
            Write-Host ""
            Write-Host "        NOTE: <DISPLAY> is not implemented yet. The first active monitor"
            Write-Host "              reported by root/WMI is used as the <DISPLAY>."
            Write-Host ""
        }
    }
} finally{
    $ddc.DestroyMonitors();
}

