# vpatt-v4l2

Minimal V4L2 capture driver for the MiniZed AXI4-Stream video pattern
generator (`hw/rtl/m_axis.v`) behind an AXI VDMA.

    m_axis_0  --AXI4-Stream-->  axi_vdma_0 S2MM  --HP0-->  DDR

`/dev/video0`, fixed **640x480 XBGR32** (`XR24`), 4 bytes/pixel,
bytesperline 2560, sizeimage 1228800.

## Kernel config required

    CONFIG_XILINX_DMA=m                  - provides the VDMA dmaengine channel
    CONFIG_VIDEO_DEV=y
    CONFIG_VIDEOBUF2_DMA_CONTIG=y
    CONFIG_DMA_CMA=y                     - contiguous buffers

Check on the target:

    zcat /proc/config.gz | grep -E 'XILINX_DMA|VIDEOBUF2_DMA_CONTIG|DMA_CMA'

## CMA

Three 1.2 MB buffers need ~4 MB of CMA. The board has 512 MB
(`reg = <0x0 0x20000000>`); if the default CMA pool is too small, raise it
on the kernel command line:
    cma=16M

