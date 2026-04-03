# MSTPD ubus Support

## What is ubus?

ubus (OpenWrt micro bus architecture) is a lightweight inter-process communication (IPC) system used primarily in OpenWrt. It provides:

- **Object-oriented RPC**: Services register objects with methods that can be called by other processes
- **Event notifications**: Publish/subscribe mechanism for system events
- **Language-agnostic**: Can be accessed from shell scripts, C programs, Lua, and other languages
- **Low overhead**: Designed for embedded systems with limited resources

In the context of mstpd, ubus allows other system components and user scripts to dynamically configure and manage spanning tree bridges without restarting the daemon or editing configuration files.

## Build Configuration

ubus support is **disabled by default** and must be explicitly enabled during the build configuration:

```bash
./configure --enable-ubus
make
```

### Dependencies

When ubus support is enabled, the following libraries are required:

- **libubox** - Core OpenWrt utility library (provides data structures, event loop helpers)
- **libubus** - OpenWrt ubus IPC library (provides RPC and messaging functionality)

If these libraries are not found, the configure script will fail with an error message. To build without ubus support, simply omit the `--enable-ubus` flag.

## ubus Interface

When compiled with ubus support, mstpd registers the `mstpd` ubus object with the following methods:

### 1. add_bridge

Configures and creates a bridge with STP/RSTP/MSTP parameters.

**Parameters:**
- `name` (string, required) - Bridge interface name
- `proto` (string, optional) - Protocol version: "stp", "rstp", or "mstp" (default: "rstp")
- `forward_delay` (int32, optional) - Bridge forward delay in seconds
- `max_age` (int32, optional) - Maximum age in seconds
- `ageing_time` (int32, optional) - MAC address ageing time in seconds

**Example:**
```bash
ubus call mstpd add_bridge '{"name":"br-lan", "proto":"rstp", "forward_delay":15, "max_age":20}'
```

**Important:** The bridge interface must already exist in the system before calling this method. Create it first with `ip link add <name> type bridge`.

### 2. delete_bridge

Removes a bridge from mstpd management and stops spanning tree operation.

**Parameters:**
- `name` (string, required) - Bridge interface name

**Example:**
```bash
ubus call mstpd delete_bridge '{"name":"br-lan"}'
```

**Note:** This does not delete the bridge interface itself from the system, only removes it from mstpd's management.

### Listing available ubus objects

```bash
# See all registered ubus objects
ubus list

# See methods available on mstpd
ubus list mstpd

# Get detailed method signatures
ubus -v list mstpd
```

## Acknowledgements

This ubus integration is based on the ustp daemon originally developed by Felix Fietkau <nbd@nbd.name> (2021) for OpenWrt.
