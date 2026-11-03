#!/usr/bin/env bash
# bluetooth menu entries, where bluetoothctl is installed and bluez answers on the bus

bluetooth::manifest() {
  fzx::entry bluetooth "Bluetooth devices"
  fzx::entry bluetooth:all "Every Bluetooth device in range or known"
}

bluetooth::applicable() {
  command -v bluetoothctl > /dev/null && command -v busctl > /dev/null &&
    command busctl --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects > /dev/null 2>&1
}

# bluetooth::summary <target>: the controller's power and the connected devices
bluetooth::summary() {
  command busctl --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects 2> /dev/null |
    command jq -r '.data[0] | [.[]] as $o |
      ([$o[] | .["org.bluez.Adapter1"] // empty][0].Powered.data) as $p |
      [$o[] | .["org.bluez.Device1"] // empty | select(.Connected.data == true) | (.Alias.data // .Name.data)] as $c |
      if $p == false then "powered off"
      elif ($c | length) == 0 then "nothing connected"
      else "\($c | length) connected: \($c | join(", "))" end'
}
