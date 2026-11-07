# Ethernet

The VENTUNO Q's 2.5 GbE port is the SoC's ETHQOS MAC (Synopsys DWC EQoS 5.20)
behind a SerDes, connected to a Qualcomm QCA8081 PHY. The PHY runs SGMII
(1.25 Gbaud) up to 1 Gbps and 2500BASE-X (3.125 Gbaud) at 2.5 Gbps, and
switches between them with the link speed.

## Fixed

| Patch | Problem | Fix |
|---|---|---|
| `linux/0004`, `linux/0005` | Upstream backports: the SerDes mode is set before power-up, and `ethqos->phy_mode` follows the interface phylink resolves | From mainline (October 2026) |
| `linux/0006` | ETHQOS reports only the device tree's `2500base-x` to phylink, which limits the PHY to 2.5 Gbps: no link with a 1 Gbps partner | Report both SGMII and 2500BASE-X |
| `linux/0007` | After a switch from SGMII to 2500BASE-X on a running interface (1 Gbps to 2.5 Gbps), the MAC passes no frames in either direction. The MAC and DMA registers match a working link apart from flow control; retuning or power cycling the SerDes and restarting autonegotiation do not help; only reopening the interface, which resets the MAC, does. The switch back to SGMII works. | Close and reopen the interface after a switch to 2500BASE-X |
| `linux/0010` | The SerDes runs on dummy regulators: the SoM device tree gives it a deprecated `phy-supply` instead of the `vdda-0p9` and `vdda-1p2` its driver takes. Its 0.9 V rail, L4A, is then held only by the display and camera PHYs; with no HDMI display, or once it is unplugged, L4A is turned off, the SerDes PLL no longer locks (`QSERDES_COM_C_READY_STATUS timed-out`, `SerDes powerup failed`) and Ethernet stops | Give the SerDes L4A and L5A |

Measured over a direct link to an RTL8156 2.5G adapter: three rounds of
1 Gbps to 2.5 Gbps and back at runtime, each passing traffic, and 2.33 Gbit/s
of TCP from the board.

## No frames received after boot

Before `linux/0010`, on about one boot in three the link came up and the
board transmitted, but the MAC received no frames until `eth0` was closed and
reopened: `mmc_rx_framecount_gb` in `ethtool -S eth0` stayed at its count at
link up, with no CRC, FIFO, buffer-unavailable or bus errors. With the SerDes
holding its own 0.9 V supply, 28 consecutive boots received frames from the
first link up.
