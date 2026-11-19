$ErrorActionPreference = 'Stop'

if (-not ('WozWorldDockProcessCommandLine' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WozWorldDockProcessCommandLine
{
    [StructLayout(LayoutKind.Sequential)]
    private struct UnicodeString
    {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, int processId);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationProcess(IntPtr process, int informationClass, IntPtr information, int informationLength, out int returnLength);

    public static string Get(int processId)
    {
        const uint ProcessQueryLimitedInformation = 0x1000;
        const int ProcessCommandLineInformation = 60;
        IntPtr process = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (process == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess could not inspect the recorded process.");

        IntPtr buffer = IntPtr.Zero;
        try
        {
            buffer = Marshal.AllocHGlobal(65536);
            int returned;
            int result = NtQueryInformationProcess(process, ProcessCommandLineInformation, buffer, 65536, out returned);
            if (result < 0)
                throw new InvalidOperationException("NtQueryInformationProcess could not read the process command line (NTSTATUS 0x" + result.ToString("X8") + ").");
            UnicodeString commandLine = Marshal.PtrToStructure<UnicodeString>(buffer);
            if (commandLine.Buffer == IntPtr.Zero || commandLine.Length == 0)
                return String.Empty;
            return Marshal.PtrToStringUni(commandLine.Buffer, commandLine.Length / 2);
        }
        finally
        {
            if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
            CloseHandle(process);
        }
    }
}
'@
}

function Get-WorldDockProcessIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ProcessId)
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) { return $null }
    $path = $null
    try { $path = $process.Path } catch { }
    $startedUtc = $null
    try { $startedUtc = $process.StartTime.ToUniversalTime().ToString('o') } catch { }
    $commandLine = [WozWorldDockProcessCommandLine]::Get($ProcessId)
    [pscustomobject]@{ Path = [string]$path; CommandLine = $commandLine; StartedUtc = $startedUtc }
}

Export-ModuleMember -Function Get-WorldDockProcessIdentity
