import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly


@cocotb.test()
async def test_vga_startup_and_timing(dut):
    # 25 MHz simulation clock.
    # Checks count pixels and lines, not elapsed seconds.
    clock = Clock(dut.clk, 40, unit="ns")

    dut.ena.value = 1
    dut.ui_in.value = 0      # 640 x 480 mode, magenta
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    cocotb.start_soon(clock.start())

    # Hold reset, then release between rising edges.
    await ClockCycles(dut.clk, 10)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    h_total = 800
    v_total = 525
    frame_pixels = h_total * v_total

    x = 0
    y = 0

    # Check two complete startup frames.
    for cycle in range(2 * frame_pixels):
        await FallingEdge(dut.clk)
        await ReadOnly()

        pins = int(dut.uo_out.value)
        hsync = (pins >> 7) & 1
        vsync = (pins >> 3) & 1
        rgb = pins & 0x77

        # Sync outputs use the previous counter values.
        expected_hsync = 0 if 656 <= x < 752 else 1
        expected_vsync = 0 if 490 <= y < 492 else 1

        assert hsync == expected_hsync, (
            f"HSYNC mismatch at cycle {cycle}: "
            f"expected {expected_hsync}, got {hsync}"
        )

        assert vsync == expected_vsync, (
            f"VSYNC mismatch at cycle {cycle}: "
            f"expected {expected_vsync}, got {vsync}"
        )

        # RGB uses the updated counter values.
        x += 1
        if x == h_total:
            x = 0
            y = (y + 1) % v_total

        if x >= 640 or y >= 480:
            assert rgb == 0, "RGB must be black during blanking"
        else:
            # Letters are still above the screen at startup.
            assert rgb == 0, "Unexpected visible pixel during startup"

        assert int(dut.uio_out.value) == 0, "Unexpected UIO output"
        assert int(dut.uio_oe.value) == 0, "UIO pins must remain inputs"

    dut._log.info(
        "PASS: two startup frames, VGA sync, blanking, and UIO"
    )
