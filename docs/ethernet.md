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

## Open: no frames received after boot

On some boots the link comes up and the board transmits, but the MAC receives
no frames: `mmc_rx_framecount_gb` in `ethtool -S eth0` stays at the count it
had at link up, with no CRC, FIFO, buffer-unavailable or bus errors, and
promiscuous mode changes nothing. The board gets no DHCP lease. Closing and
reopening `eth0` fixes it until the next boot; `ventuno-q-eth-watch` does
that 20 seconds after the first link up, so an affected boot reaches the
network about 40 seconds after power on.

What is known:

- It happens at 1 Gbps and at 2.5 Gbps, with the device tree in SGMII or
  2500BASE-X, and so without any mode switch.
- It never happens on an open later in the boot: every restart by the
  watcher, about 40 seconds after power on, worked.
- Link renegotiation on a running interface (`ethtool -r`, five times) does
  not cause it.
- It is not the first open after power on: with `eth0` opened and closed once
  before the Erlang VM starts, so that VintageNet's open at about 4 seconds is
  the second, 4 boots out of 8 still stalled.
- It is not the DSPs: with `qcom_q6v5_pas` blacklisted (no ADSP, CDSP or
  GPDSP), 6 boots out of 10 stalled, against 2 out of 6 with them.
- The kernel log of a stalled boot is the same as that of a clean one apart
  from the RTC time. `rpmh_write_batch` timeout warnings appear on some boots
  and do not follow the stalls.
- The PHY's reset timing matches the vendor device tree (11 ms asserted,
  70 ms before use).

The next step is to hold the first open of `eth0` until about 15 seconds after
power on. If the stalls disappear, bisect which start-up event between 3 and
15 seconds breaks a MAC that is already open (the integrated PCS's in-band
autonegotiation restarts several times between 4 and 5 seconds, while other
drivers probe).

## Measuring

Reboot over the debug UART, wait for SSH, and count
`ventuno-q-eth-watch: no frames received` in the kernel log of each boot. Rates vary: 2 of 6 boots on one run, 5 of 6 and 1 of 4 on two runs of
the same configuration. Compare configurations over at least 8 boots each.
