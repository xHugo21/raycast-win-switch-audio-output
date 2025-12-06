# Windows Audio Device Manager PowerShell Script
# Simplified approach using Windows Core Audio API

param(
    [Parameter(Mandatory=$true)]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$DeviceId
)

# Check if we're running on Windows
if ($PSVersionTable.Platform -eq "Unix") {
    Write-Error "This script requires Windows"
    exit 1
}

# Define audio device helper
$code = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

namespace AudioSwitcher
{
    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject
    {
    }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig]
        int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IMMDeviceCollection ppDevices);
        [PreserveSig]
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
        [PreserveSig]
        int GetDevice(string pwstrId, out IMMDevice ppDevice);
        [PreserveSig]
        int RegisterEndpointNotificationCallback(IntPtr pClient); // not used
        [PreserveSig]
        int UnregisterEndpointNotificationCallback(IntPtr pClient); // not used
    }

    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        [PreserveSig]
        int GetCount(out int pcDevices);
        [PreserveSig]
        int Item(int nDevice, out IMMDevice ppDevice);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IntPtr ppInterface);
        [PreserveSig]
        int OpenPropertyStore(int stgmAccess, out IPropertyStore ppProperties);
        [PreserveSig]
        int GetId(out IntPtr ppstrId);
        [PreserveSig]
        int GetState(out int pdwState);
    }

    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        [PreserveSig]
        int GetCount(out int cProps);
        [PreserveSig]
        int GetAt(int iProp, out PropertyKey pkey);
        [PreserveSig]
        int GetValue(ref PropertyKey key, out PropVariant pv);
        [PreserveSig]
        int SetValue(ref PropertyKey key, ref PropVariant propvar);
        [PreserveSig]
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropertyKey
    {
        public Guid fmtid;
        public int pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct PropVariant
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pwszVal;
    }

    [Guid("F8679F50-850A-41CF-9C72-430F290290C8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPolicyConfig
    {
        [PreserveSig]
        int GetMixFormat(string pszDeviceName, IntPtr ppFormat);
        [PreserveSig]
        int GetDeviceFormat(string pszDeviceName, bool bDefault, IntPtr ppFormat);
        [PreserveSig]
        int ResetDeviceFormat(string pszDeviceName);
        [PreserveSig]
        int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr MixFormat);
        [PreserveSig]
        int GetProcessingPeriod(string pszDeviceName, bool bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
        [PreserveSig]
        int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);
        [PreserveSig]
        int GetShareMode(string pszDeviceName, IntPtr pMode);
        [PreserveSig]
        int SetShareMode(string pszDeviceName, IntPtr mode);
        [PreserveSig]
        int GetPropertyValue(string pszDeviceName, bool bFxStore, ref PropertyKey key, out PropVariant pv);
        [PreserveSig]
        int SetPropertyValue(string pszDeviceName, bool bFxStore, ref PropertyKey key, ref PropVariant pv);
        [PreserveSig]
        int SetDefaultEndpoint(string pszDeviceName, int role);
        [PreserveSig]
        int SetEndpointVisibility(string pszDeviceName, bool bVisible);
    }

    [ComImport]
    [Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
    internal class CPolicyConfigClientComObject
    {
    }

    public class AudioDevice
    {
        public string Name { get; set; }
        public string Id { get; set; }
        public string Uid { get; set; }
        public bool IsOutput { get; set; }
        public bool IsInput { get; set; }
        public string TransportType { get; set; }
        public bool IsDefault { get; set; }
    }

    public class AudioController
    {
        private static PropertyKey PKEY_Device_FriendlyName = new PropertyKey
        {
            fmtid = new Guid(0xa45c254e, 0xdf1c, 0x4efd, 0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0),
            pid = 14
        };

        public static List<AudioDevice> GetPlaybackDevices()
        {
            string stage = "start";
            var deviceList = new List<AudioDevice>();
            IMMDeviceEnumerator enumerator = null;
            IMMDeviceCollection collection = null;
            IMMDevice defaultDevice = null;

            try
            {
                stage = "create enumerator";
                enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                if (enumerator == null)
                    throw new Exception("Failed to create MMDeviceEnumerator");
                
                stage = "enum endpoints";
                int hr = enumerator.EnumAudioEndpoints(0, 1, out collection); // 0 = eRender, 1 = DEVICE_STATE_ACTIVE
                if (hr != 0)
                    throw new Exception(string.Format("EnumAudioEndpoints failed with HRESULT: 0x{0:X8}", hr));

                if (collection == null)
                    throw new Exception("EnumAudioEndpoints returned null collection");
                
                stage = "get count";
                int count;
                hr = collection.GetCount(out count);
                if (hr != 0)
                    throw new Exception(string.Format("GetCount failed with HRESULT: 0x{0:X8}", hr));

                stage = "get default endpoint";
                hr = enumerator.GetDefaultAudioEndpoint(0, 0, out defaultDevice); // 0 = eRender, 0 = eConsole
                if (hr != 0 || defaultDevice == null)
                    throw new Exception(string.Format("GetDefaultAudioEndpoint failed with HRESULT: 0x{0:X8}", hr));
                string defaultId = "";
                try
                {
                    IntPtr defaultIdPtr;
                    defaultDevice.GetId(out defaultIdPtr);
                    if (defaultIdPtr != IntPtr.Zero)
                    {
                        defaultId = Marshal.PtrToStringUni(defaultIdPtr);
                        Marshal.FreeCoTaskMem(defaultIdPtr);
                    }
                }
                catch { /* ignore, fallback to empty defaultId */ }

                for (int i = 0; i < count; i++)
                {
                    stage = "iterating device " + i;
                    IMMDevice device = null;
                    IPropertyStore propertyStore = null;

                    try
                {
                    stage = "collection.Item " + i;
                    hr = collection.Item(i, out device);
                    if (hr != 0 || device == null)
                        continue;

                    stage = "device.GetId " + i;
                    IntPtr idPtr;
                    hr = device.GetId(out idPtr);
                    if (hr != 0 || idPtr == IntPtr.Zero)
                        continue;
                    string id = Marshal.PtrToStringUni(idPtr);
                    Marshal.FreeCoTaskMem(idPtr);
                    if (string.IsNullOrWhiteSpace(id))
                        continue;

                        stage = "device.OpenPropertyStore " + i;
                        hr = device.OpenPropertyStore(0, out propertyStore); // 0 = STGM_READ
                        if (hr != 0 || propertyStore == null)
                            continue;

                        stage = "propertyStore.GetValue " + i;
                        PropVariant nameVariant;
                        hr = propertyStore.GetValue(ref PKEY_Device_FriendlyName, out nameVariant);
                        string name = "Unknown Device";
                        if (hr == 0 && nameVariant.pwszVal != IntPtr.Zero)
                        {
                            name = Marshal.PtrToStringUni(nameVariant.pwszVal);
                        }

                        deviceList.Add(new AudioDevice
                        {
                            Name = name ?? "Unknown Device",
                            Id = id,
                            Uid = id,
                            IsOutput = true,
                            IsInput = false,
                            TransportType = "unknown",
                            IsDefault = id == defaultId
                        });
                    }
                    finally
                    {
                        if (propertyStore != null)
                            Marshal.ReleaseComObject(propertyStore);
                        if (device != null)
                            Marshal.ReleaseComObject(device);
                    }
                }
            }
            catch (Exception ex)
            {
                throw new Exception("GetPlaybackDevices failed at stage " + stage + ": " + ex.ToString(), ex);
            }
            finally
            {
                if (defaultDevice != null)
                    Marshal.ReleaseComObject(defaultDevice);
                if (collection != null)
                    Marshal.ReleaseComObject(collection);
                if (enumerator != null)
                    Marshal.ReleaseComObject(enumerator);
            }

            return deviceList;
        }

        public static AudioDevice GetDefaultDevice()
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            IPropertyStore propertyStore = null;

            try
            {
                enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                if (enumerator == null)
                    throw new Exception("Failed to create MMDeviceEnumerator");
                
                int hr = enumerator.GetDefaultAudioEndpoint(0, 0, out device); // 0 = eRender, 0 = eConsole
                if (hr != 0 || device == null)
                    throw new Exception(string.Format("GetDefaultAudioEndpoint failed with HRESULT: 0x{0:X8}", hr));

                IntPtr idPtr;
                hr = device.GetId(out idPtr);
                if (hr != 0 || idPtr == IntPtr.Zero)
                    throw new Exception(string.Format("GetId failed with HRESULT: 0x{0:X8}", hr));
                string id = Marshal.PtrToStringUni(idPtr);
                Marshal.FreeCoTaskMem(idPtr);

                hr = device.OpenPropertyStore(0, out propertyStore);
                if (hr != 0 || propertyStore == null)
                    throw new Exception(string.Format("OpenPropertyStore failed with HRESULT: 0x{0:X8}", hr));

                PropVariant nameVariant;
                hr = propertyStore.GetValue(ref PKEY_Device_FriendlyName, out nameVariant);
                string name = "Unknown Device";
                if (hr == 0 && nameVariant.pwszVal != IntPtr.Zero)
                {
                    name = Marshal.PtrToStringUni(nameVariant.pwszVal);
                }

                return new AudioDevice
                {
                    Name = name ?? "Unknown Device",
                    Id = id,
                    Uid = id,
                    IsOutput = true,
                    IsInput = false,
                    TransportType = "unknown",
                    IsDefault = true
                };
            }
            finally
            {
                if (propertyStore != null)
                    Marshal.ReleaseComObject(propertyStore);
                if (device != null)
                    Marshal.ReleaseComObject(device);
                if (enumerator != null)
                    Marshal.ReleaseComObject(enumerator);
            }
        }

        public static void SetDefaultDevice(string deviceId)
        {
            IPolicyConfig policyConfig = null;
            
            try
            {
                policyConfig = (IPolicyConfig)new CPolicyConfigClientComObject();
                if (policyConfig == null)
                    throw new Exception("Failed to create CPolicyConfigClient");

                int hr = policyConfig.SetDefaultEndpoint(deviceId, 0); // eConsole
                if (hr != 0)
                    throw new Exception(string.Format("SetDefaultEndpoint (Console) failed with HRESULT: 0x{0:X8}", hr));

                hr = policyConfig.SetDefaultEndpoint(deviceId, 1); // eMultimedia  
                if (hr != 0)
                    throw new Exception(string.Format("SetDefaultEndpoint (Multimedia) failed with HRESULT: 0x{0:X8}", hr));

                hr = policyConfig.SetDefaultEndpoint(deviceId, 2); // eCommunications
                if (hr != 0)
                    throw new Exception(string.Format("SetDefaultEndpoint (Communications) failed with HRESULT: 0x{0:X8}", hr));
            }
            finally
            {
                if (policyConfig != null)
                    Marshal.ReleaseComObject(policyConfig);
            }
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $code -Language CSharp -IgnoreWarnings -ErrorAction Stop
} catch {
    if ($_.Exception.Message -like "*Cannot add type*" -and $_.Exception.Message -like "*already exists*") {
        # Type already loaded, continue
    } else {
        Write-Error "Failed to load audio controller: $($_.Exception.Message)"
        exit 1
    }
}

# Execute requested action
try {
    switch ($Action.ToLower()) {
        "list" {
            $devices = [AudioSwitcher.AudioController]::GetPlaybackDevices()
            $deviceArray = @()
            foreach ($dev in $devices) {
                $deviceArray += @{
                    name = $dev.Name
                    id = $dev.Id
                    uid = $dev.Uid
                    isOutput = $dev.IsOutput
                    isInput = $dev.IsInput
                    transportType = $dev.TransportType
                    isDefault = $dev.IsDefault
                }
            }
            $json = ConvertTo-Json -InputObject $deviceArray -Depth 10 -Compress
            Write-Output $json
        }
        "get-default" {
            $device = [AudioSwitcher.AudioController]::GetDefaultDevice()
            $deviceObj = @{
                name = $device.Name
                id = $device.Id
                uid = $device.Uid
                isOutput = $device.IsOutput
                isInput = $device.IsInput
                transportType = $device.TransportType
                isDefault = $device.IsDefault
            }
            $json = $deviceObj | ConvertTo-Json -Depth 10 -Compress
            Write-Output $json
        }
        "set-default" {
            if (-not $DeviceId) {
                throw "DeviceId parameter is required for set-default action"
            }
            [AudioSwitcher.AudioController]::SetDefaultDevice($DeviceId)
            Write-Output "Success"
        }
        default {
            throw "Unknown action: $Action. Valid actions are: list, get-default, set-default"
        }
    }
} catch {
    Write-Error "Error executing action '$Action': $($_.Exception.Message)"
    exit 1
}
