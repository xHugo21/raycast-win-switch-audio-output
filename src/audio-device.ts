import path from "path";
import { execa } from "execa";
import { environment } from "@raycast/api";

export enum TransportType {
  Usb = "usb",
  Bluetooth = "bluetooth",
  HDMI = "hdmi",
  BuiltIn = "builtin",
  Virtual = "virtual",
  Unknown = "unknown",
}

export type AudioDevice = {
  name: string;
  isInput: boolean;
  isOutput: boolean;
  id: string;
  uid: string;
  transportType: TransportType;
};

const scriptPath = path.join(environment.assetsPath, "audio-devices.ps1");

function parseStdout({ stdout, stderr }: { stderr: string; stdout: string }): any {
  if (stderr?.trim()) {
    console.warn("PowerShell stderr:", stderr);
  }

  let trimmed = stdout?.trim() ?? "";
  if (trimmed.startsWith("\ufeff")) {
    trimmed = trimmed.slice(1);
  }
  if (!trimmed) {
    throw new Error("PowerShell returned no data");
  }

  try {
    return JSON.parse(trimmed);
  } catch (e) {
    console.error("Failed to parse JSON:", trimmed);
    throw new Error(`Failed to parse JSON response: ${e}`);
  }
}

async function runPowerShell(action: string, deviceId?: string): Promise<{ stdout: string; stderr: string }> {
  const args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "-Action", action];

  if (deviceId) {
    args.push("-DeviceId", deviceId);
  }

  return await execa("powershell.exe", args);
}

export async function getOutputDevices(): Promise<AudioDevice[]> {
  const parsed = parseStdout(await runPowerShell("list"));
  if (Array.isArray(parsed)) return parsed;
  if (parsed && typeof parsed === "object") {
    console.warn("Coercing object list payload into array:", parsed);
    return [parsed as AudioDevice];
  }
  console.warn("Unexpected list payload:", parsed);
  return [];
}

export async function getDefaultOutputDevice(): Promise<AudioDevice> {
  const parsed = parseStdout(await runPowerShell("get-default"));
  return parsed as AudioDevice;
}

export async function setDefaultOutputDevice(deviceId: string): Promise<void> {
  const { stderr } = await runPowerShell("set-default", deviceId);
  if (stderr?.trim()) {
    console.warn("PowerShell stderr:", stderr);
  }
}
