import {
  Action,
  ActionPanel,
  Color,
  closeMainWindow,
  Icon,
  Keyboard,
  List,
  LocalStorage,
  popToRoot,
  showHUD,
  showToast,
  Toast,
} from "@raycast/api";
import { useFrecencySorting, usePromise } from "@raycast/utils";
import { useEffect } from "react";
import {
  type AudioDevice,
  getDefaultOutputDevice,
  getOutputDevices,
  setDefaultOutputDevice,
  TransportType,
} from "./audio-device";

type DeviceListProps = {
  deviceId?: string;
  deviceName?: string;
};

export function DeviceList({ deviceId, deviceName }: DeviceListProps) {
  const { isLoading, data, error } = useAudioDevices();
  const { data: hiddenDevices } = usePromise(getHiddenDevices, []);
  const { data: showHidden, revalidate: refetchShowHidden } = usePromise(isShowingHiddenDevices, []);

  const visibleDevices =
    data?.devices
      ?.filter((d) => d.id && d.uid && !hiddenDevices?.includes(d.uid))
      ?.map((d) => ({ ...d, uid: d.uid || d.id })) || [];

  const { data: sortedDevices = [], visitItem: recordDeviceSelection } = useFrecencySorting(visibleDevices, {
    key: (device) => device.uid || device.id || device.name,
  });

  useEffect(() => {
    if ((!deviceId && !deviceName) || !data?.devices) return;

    let device = null;
    if (deviceId) device = data.devices.find((d) => d.id === deviceId);
    if (!device && deviceName) device = data.devices.find((d) => d.name === deviceName);

    if (!device) {
      const searchCriteria = deviceId ? `id ${deviceId}` : `name "${deviceName}"`;
      showToast(Toast.Style.Failure, "Error!", `The device with ${searchCriteria} was not found.`);
      return;
    }

    (async () => {
      try {
        await setDefaultOutputDevice(device.id);
        recordDeviceSelection(device);
        closeMainWindow({ clearRootSearch: true });
        popToRoot({ clearSearchBar: true });
        showHUD(`Active output audio device set to ${device.name}`);
      } catch (e) {
        console.log(e);
        showToast(
          Toast.Style.Failure,
          `Error!`,
          `There was an error setting the active output audio device to ${device.name}`,
        );
      }
    })();
  }, [deviceId, deviceName, data, recordDeviceSelection]);

  const noVisibleDevices = !isLoading && sortedDevices.length === 0;

  if (error) {
    return (
      <List isLoading={isLoading}>
        <List.EmptyView
          title="Failed to load devices"
          description={getErrorMessage(error)}
          icon={Icon.ExclamationMark}
          actions={
            <ActionPanel>
              <Action.CopyToClipboard title="Copy Error" content={getErrorMessage(error)} />
            </ActionPanel>
          }
        />
      </List>
    );
  }

  return (
    <List isLoading={isLoading}>
      {noVisibleDevices && (
        <List.EmptyView
          title={hiddenDevices?.length ? "No devices to show" : "No output devices found"}
          description={
            hiddenDevices?.length
              ? "All devices are hidden. Tap Enter to show hidden devices."
              : "No devices returned by the system. Check device connections or permissions."
          }
          actions={
            hiddenDevices?.length ? (
              <ActionPanel>
                <ToggleShowHiddenDevicesAction onAction={refetchShowHidden} />
              </ActionPanel>
            ) : undefined
          }
        />
      )}
      {data &&
        sortedDevices.map((d, index) => {
          const isCurrent = d.uid === data?.current?.uid;
          return (
            <List.Item
              key={d.uid || d.id || d.name || String(index)}
              title={d.name}
              subtitle={getSubtitle(d)}
              icon={getIcon(d, isCurrent)}
              actions={
                <ActionPanel>
                  <DeviceActions device={d} onSelection={() => recordDeviceSelection(d)} />
                </ActionPanel>
              }
              accessories={getAccessories(isCurrent)}
            />
          );
        })}
      {showHidden && data && (
        <List.Section title="Hidden Devices">
          {data.devices
            .filter((d) => hiddenDevices?.includes(d.uid))
            .map((d, index) => (
              <List.Item
                key={d.uid || d.id || d.name || `hidden-${index}`}
                title={d.name}
                subtitle={getSubtitle(d)}
                icon={getIcon(d, false)}
                actions={
                  <ActionPanel>
                    <DeviceActions device={d} onSelection={() => recordDeviceSelection(d)} />
                  </ActionPanel>
                }
              />
            ))}
        </List.Section>
      )}
    </List>
  );
}

function DeviceActions({ device, onSelection }: { device: AudioDevice; onSelection: () => void }) {
  const { revalidate: refetchHiddenDevices } = usePromise(getHiddenDevices, []);
  const { revalidate: refetchShowHidden } = usePromise(isShowingHiddenDevices, []);

  return (
    <>
      <SetAudioDeviceAction device={device} onSelection={onSelection} />
      <Action.CopyToClipboard title="Copy Device Name" content={device.name} shortcut={Keyboard.Shortcut.Common.Copy} />
      <ToggleDeviceVisibilityAction deviceId={device.uid} onAction={refetchHiddenDevices} />

      <ActionPanel.Section title="Options">
        <ToggleShowHiddenDevicesAction onAction={refetchShowHidden} />
      </ActionPanel.Section>
    </>
  );
}

function useAudioDevices() {
  return usePromise(async () => {
    const devices = await getOutputDevices();
    const current = await getDefaultOutputDevice();

    return {
      devices: devices || [],
      current,
    };
  }, []);
}

type SetAudioDeviceActionProps = {
  device: AudioDevice;
  onSelection?: () => void;
};

function SetAudioDeviceAction({ device, onSelection }: SetAudioDeviceActionProps) {
  return (
    <Action
      title="Set as Output Device"
      icon={{
        source: Icon.Speaker,
        tintColor: Color.PrimaryText,
      }}
      onAction={async () => {
        try {
          await setDefaultOutputDevice(device.id);
          onSelection?.();
          closeMainWindow({ clearRootSearch: true });
          popToRoot({ clearSearchBar: true });
          showHUD(`Set "${device.name}" as output device`);
        } catch (e) {
          console.log(e);
          showToast(Toast.Style.Failure, `Failed setting "${device.name}" as output device`);
        }
      }}
    />
  );
}

function ToggleDeviceVisibilityAction({ deviceId, onAction }: { deviceId: string; onAction: () => void }) {
  const { data: isHidden, revalidate: refetchIsHidden } = usePromise(async () => {
    const hiddenDevices = await getHiddenDevices();
    return hiddenDevices.includes(deviceId);
  }, []);

  return (
    <Action
      title={isHidden ? "Show Device" : "Hide Device"}
      icon={isHidden ? Icon.Eye : Icon.EyeDisabled}
      shortcut={{ modifiers: ["cmd"], key: "h" }}
      onAction={async () => {
        await toggleDeviceVisibility(deviceId);
        refetchIsHidden();
        onAction();
      }}
    />
  );
}

function ToggleShowHiddenDevicesAction({ onAction }: { onAction: () => void }) {
  const { data: showHidden, revalidate: refetchShowHidden } = usePromise(async () => {
    return (await LocalStorage.getItem("showHiddenDevices")) === "true";
  }, []);

  return (
    <Action
      title={showHidden ? "Hide Hidden Devices" : "Show Hidden Devices"}
      icon={showHidden ? Icon.EyeDisabled : Icon.Eye}
      onAction={async () => {
        await LocalStorage.setItem("showHiddenDevices", showHidden ? "false" : "true");
        refetchShowHidden();
        onAction();
      }}
    />
  );
}

async function toggleDeviceVisibility(deviceId: string) {
  const hiddenDevices = JSON.parse((await LocalStorage.getItem("hiddenDevices")) || "[]");
  const index = hiddenDevices.indexOf(deviceId);
  if (index === -1) {
    hiddenDevices.push(deviceId);
  } else {
    hiddenDevices.splice(index, 1);
  }
  await LocalStorage.setItem("hiddenDevices", JSON.stringify(hiddenDevices));
}

async function getHiddenDevices(): Promise<string[]> {
  return JSON.parse((await LocalStorage.getItem("hiddenDevices")) || "[]");
}

async function isShowingHiddenDevices(): Promise<boolean> {
  return (await LocalStorage.getItem("showHiddenDevices")) === "true";
}

function getIcon(device: AudioDevice, isCurrent: boolean) {
  let iconSource = Icon.Speaker;

  // Determine icon based on transport type
  if (device.transportType === TransportType.Bluetooth) {
    iconSource = Icon.Bluetooth;
  } else if (device.transportType === TransportType.Usb) {
    iconSource = Icon.ComputerChip;
  } else if (device.transportType === TransportType.HDMI) {
    iconSource = Icon.Display;
  }

  return {
    source: iconSource,
    tintColor: isCurrent ? Color.Green : Color.SecondaryText,
  };
}

function getAccessories(isCurrent: boolean) {
  return [
    {
      icon: isCurrent ? Icon.Checkmark : undefined,
    },
  ];
}

function getSubtitle(device: AudioDevice) {
  return Object.entries(TransportType).find(([, v]) => v === device.transportType)?.[0];
}

function getErrorMessage(error: unknown) {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  try {
    return JSON.stringify(error);
  } catch {
    return "Unknown error";
  }
}
