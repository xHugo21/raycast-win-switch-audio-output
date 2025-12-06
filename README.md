# Windows Audio Output

A Raycast extension for Windows that allows you to quickly switch between audio output devices.

## Features

- **Quick Device Switching**: View all available audio output devices and switch between them instantly
- **Frecency Sorting**: Devices are sorted based on frequency and recency of use
- **Device Management**: Hide devices you don't use frequently
- **Keyboard Shortcuts**:
  - `Enter` - Set the selected device as the default output
  - `Cmd+C` - Copy device name to clipboard
  - `Cmd+H` - Hide/show device from the list

## How It Works

This extension uses PowerShell with Windows Core Audio APIs to enumerate and manage audio devices. The PowerShell script communicates with the Windows MMDevice API to:

- List all active playback devices
- Get the current default device
- Set a new default playback device

## Requirements

- Windows 10 or later
- Raycast for Windows
- PowerShell (built-in on Windows)

## Installation

1. Clone or download this extension
2. Run `npm install` to install dependencies
3. Run `npm run dev` to start development mode
4. Use Raycast to test the extension

## Usage

1. Open Raycast and search for "Set Audio Output"
2. Browse the list of available audio devices
3. Press Enter on any device to set it as the default output
4. The device will be remembered and prioritized in future searches

## Technical Details

The extension consists of:

- **audio-devices.ps1**: PowerShell script that interfaces with Windows Core Audio APIs
- **audio-device.ts**: TypeScript wrapper for executing PowerShell commands
- **helpers.tsx**: React component for displaying and managing the device list
- **set-audio-output.tsx**: Main command entry point

## License

MIT
