// SPDX-License-Identifier: GPL-2.0
/*
 * vpatt-v4l2 - minimal V4L2 capture driver for the MiniZed video pattern
 * generator.
 *
 * Hardware:
 *
 *   m_axis_0 (rtl/m_axis.v)  --AXI4-Stream-->  axi_vdma_0 S2MM  -->  DDR
 *
 * m_axis_0 is a free-running AXI4-Stream master: no AXI-Lite interface, no
 * registers, nothing to start or stop.  It emits tuser on the first pixel of
 * a frame (SOF) and tlast on the last pixel of a line (EOL), which is exactly
 * what the VDMA needs to frame-sync, so the whole capture path is just "point
 * the VDMA at a buffer and let it fill".
 *
 * That is why this is a plain platform driver over dmaengine rather than a
 * Xilinx VIPP pipeline: with no subdev to negotiate a format with, the media
 * graph in xilinx-vipp would never complete.  Here the format is fixed at
 * probe from the device tree and never changes.
 *
 * Pixel format: the core drives tdata = {8'h00, R[7:0], G[7:0], B[7:0]}.
 * Little-endian, that lands in memory as B, G, R, X -- V4L2_PIX_FMT_XBGR32.
 */

#include <linux/dma-mapping.h>
#include <linux/dmaengine.h>
#include <linux/list.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_reserved_mem.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/spinlock.h>

#include <media/v4l2-device.h>
#include <media/v4l2-ioctl.h>
#include <media/videobuf2-dma-contig.h>
#include <media/videobuf2-v4l2.h>

#define VPATT_DRV_NAME		"vpatt-v4l2"

#define VPATT_DEF_WIDTH		640
#define VPATT_DEF_HEIGHT	480
#define VPATT_BPP		4			/* {X, R, G, B} */
#define VPATT_PIXELFORMAT	V4L2_PIX_FMT_XBGR32

/* The VDMA is built without DRE (C_INCLUDE_S2MM_DRE = 0), so buffer
 * addresses must be aligned to the memory-map data width (64 bit).
 * videobuf2-dma-contig hands out page-aligned buffers, so this only ever
 * matters as a sanity check.
 */
#define VPATT_ADDR_ALIGN	8

struct vpatt_buffer {
	struct vb2_v4l2_buffer	vb;
	struct list_head	queue;
	struct vpatt_dev	*vpatt;
};

struct vpatt_dev {
	struct device		*dev;
	struct v4l2_device	v4l2_dev;
	struct video_device	vdev;
	struct vb2_queue	queue;

	/* Serialises ioctls and vb2 operations. */
	struct mutex		lock;
	/* Protects buf_list and sequence against the DMA completion callback. */
	spinlock_t		qlock;
	struct list_head	buf_list;

	struct dma_chan		*dma;
	struct v4l2_pix_format	format;
	unsigned int		sequence;

	/*
	 * dma_interleaved_template ends in a flexible sgl[] array, so it has
	 * to be followed immediately by the chunk it describes.  Same trick
	 * the in-tree xilinx-dma driver uses.  Only touched from buf_queue(),
	 * which vb2 serialises under queue->lock.
	 */
	struct dma_interleaved_template xt;
	struct data_chunk	sgl[1];
};

static inline struct vpatt_buffer *to_vpatt_buffer(struct vb2_v4l2_buffer *vbuf)
{
	return container_of(vbuf, struct vpatt_buffer, vb);
}

/* -------------------------------------------------------------------------
 * DMA
 */

static void vpatt_dma_complete(void *param)
{
	struct vpatt_buffer *buf = param;
	struct vpatt_dev *vpatt = buf->vpatt;
	unsigned long flags;

	spin_lock_irqsave(&vpatt->qlock, flags);
	list_del_init(&buf->queue);
	buf->vb.sequence = vpatt->sequence++;
	spin_unlock_irqrestore(&vpatt->qlock, flags);

	buf->vb.field = V4L2_FIELD_NONE;
	buf->vb.vb2_buf.timestamp = ktime_get_ns();
	vb2_set_plane_payload(&buf->vb.vb2_buf, 0, vpatt->format.sizeimage);
	vb2_buffer_done(&buf->vb.vb2_buf, VB2_BUF_STATE_DONE);
}

/* Hand every buffer we still own back to vb2 with the given state. */
static void vpatt_return_all_buffers(struct vpatt_dev *vpatt,
				     enum vb2_buffer_state state)
{
	struct vpatt_buffer *buf, *tmp;
	unsigned long flags;

	spin_lock_irqsave(&vpatt->qlock, flags);
	list_for_each_entry_safe(buf, tmp, &vpatt->buf_list, queue) {
		list_del_init(&buf->queue);
		spin_unlock_irqrestore(&vpatt->qlock, flags);
		vb2_buffer_done(&buf->vb.vb2_buf, state);
		spin_lock_irqsave(&vpatt->qlock, flags);
	}
	spin_unlock_irqrestore(&vpatt->qlock, flags);
}

/* -------------------------------------------------------------------------
 * videobuf2
 */

static int vpatt_queue_setup(struct vb2_queue *vq, unsigned int *nbuffers,
			     unsigned int *nplanes, unsigned int sizes[],
			     struct device *alloc_devs[])
{
	struct vpatt_dev *vpatt = vb2_get_drv_priv(vq);
	unsigned int size = vpatt->format.sizeimage;

	if (*nplanes) {
		/* Called with a format already proposed - just validate it. */
		return sizes[0] < size ? -EINVAL : 0;
	}

	*nplanes = 1;
	sizes[0] = size;

	/*
	 * The VDMA is built with 4 frame stores; give it at least three
	 * buffers so userspace holding one still leaves the hardware two to
	 * ping-pong between.
	 */
	if (*nbuffers < 3)
		*nbuffers = 3;

	return 0;
}

static int vpatt_buf_prepare(struct vb2_buffer *vb)
{
	struct vpatt_dev *vpatt = vb2_get_drv_priv(vb->vb2_queue);
	unsigned long size = vpatt->format.sizeimage;

	if (vb2_plane_size(vb, 0) < size) {
		dev_err(vpatt->dev, "buffer too small (%lu < %lu)\n",
			vb2_plane_size(vb, 0), size);
		return -EINVAL;
	}

	vb2_set_plane_payload(vb, 0, size);
	return 0;
}

static void vpatt_buf_queue(struct vb2_buffer *vb)
{
	struct vpatt_dev *vpatt = vb2_get_drv_priv(vb->vb2_queue);
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct vpatt_buffer *buf = to_vpatt_buffer(vbuf);
	struct dma_async_tx_descriptor *desc;
	dma_addr_t addr = vb2_dma_contig_plane_dma_addr(vb, 0);
	unsigned long flags;

	if (!IS_ALIGNED(addr, VPATT_ADDR_ALIGN)) {
		dev_err(vpatt->dev, "buffer at %pad is not %u-byte aligned\n",
			&addr, VPATT_ADDR_ALIGN);
		vb2_buffer_done(vb, VB2_BUF_STATE_ERROR);
		return;
	}

	/*
	 * One "frame" of numf lines, each sgl[0].size bytes long with icg
	 * bytes of padding to the next line.  With no padding this is simply
	 * a linear height x bytesperline transfer.
	 */
	vpatt->xt.dir = DMA_DEV_TO_MEM;
	vpatt->xt.src_sgl = false;
	vpatt->xt.dst_sgl = true;
	vpatt->xt.dst_start = addr;
	vpatt->xt.frame_size = 1;
	vpatt->xt.numf = vpatt->format.height;
	vpatt->sgl[0].size = vpatt->format.width * VPATT_BPP;
	vpatt->sgl[0].icg = vpatt->format.bytesperline - vpatt->sgl[0].size;

	desc = dmaengine_prep_interleaved_dma(vpatt->dma, &vpatt->xt,
					      DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
	if (!desc) {
		dev_err(vpatt->dev, "failed to prepare DMA descriptor\n");
		vb2_buffer_done(vb, VB2_BUF_STATE_ERROR);
		return;
	}

	buf->vpatt = vpatt;
	desc->callback = vpatt_dma_complete;
	desc->callback_param = buf;

	spin_lock_irqsave(&vpatt->qlock, flags);
	list_add_tail(&buf->queue, &vpatt->buf_list);
	spin_unlock_irqrestore(&vpatt->qlock, flags);

	dmaengine_submit(desc);

	if (vb2_start_streaming_called(&vpatt->queue))
		dma_async_issue_pending(vpatt->dma);
}

static int vpatt_start_streaming(struct vb2_queue *vq, unsigned int count)
{
	struct vpatt_dev *vpatt = vb2_get_drv_priv(vq);

	vpatt->sequence = 0;
	dma_async_issue_pending(vpatt->dma);

	return 0;
}

static void vpatt_stop_streaming(struct vb2_queue *vq)
{
	struct vpatt_dev *vpatt = vb2_get_drv_priv(vq);

	dmaengine_terminate_sync(vpatt->dma);
	vpatt_return_all_buffers(vpatt, VB2_BUF_STATE_ERROR);
}

static const struct vb2_ops vpatt_qops = {
	.queue_setup		= vpatt_queue_setup,
	.buf_prepare		= vpatt_buf_prepare,
	.buf_queue		= vpatt_buf_queue,
	.start_streaming	= vpatt_start_streaming,
	.stop_streaming		= vpatt_stop_streaming,
	.wait_prepare		= vb2_ops_wait_prepare,
	.wait_finish		= vb2_ops_wait_finish,
};

/* -------------------------------------------------------------------------
 * V4L2 ioctls
 *
 * The format is fixed by the hardware, so s_fmt/try_fmt just report it back
 * rather than failing - that keeps naive applications (and GStreamer's
 * v4l2src) happy.
 */

static int vpatt_querycap(struct file *file, void *priv,
			  struct v4l2_capability *cap)
{
	strscpy(cap->driver, VPATT_DRV_NAME, sizeof(cap->driver));
	strscpy(cap->card, "MiniZed video pattern generator", sizeof(cap->card));
	return 0;
}

static int vpatt_enum_fmt(struct file *file, void *priv,
			  struct v4l2_fmtdesc *f)
{
	if (f->index > 0)
		return -EINVAL;

	f->pixelformat = VPATT_PIXELFORMAT;
	return 0;
}

static int vpatt_g_fmt(struct file *file, void *priv, struct v4l2_format *f)
{
	struct vpatt_dev *vpatt = video_drvdata(file);

	f->fmt.pix = vpatt->format;
	return 0;
}

static int vpatt_try_fmt(struct file *file, void *priv, struct v4l2_format *f)
{
	struct vpatt_dev *vpatt = video_drvdata(file);

	/* Nothing is negotiable - the pattern generator is hard-wired. */
	f->fmt.pix = vpatt->format;
	return 0;
}

static int vpatt_enum_framesizes(struct file *file, void *priv,
				 struct v4l2_frmsizeenum *fsize)
{
	struct vpatt_dev *vpatt = video_drvdata(file);

	if (fsize->index > 0 || fsize->pixel_format != VPATT_PIXELFORMAT)
		return -EINVAL;

	fsize->type = V4L2_FRMSIZE_TYPE_DISCRETE;
	fsize->discrete.width = vpatt->format.width;
	fsize->discrete.height = vpatt->format.height;
	return 0;
}

static int vpatt_enum_input(struct file *file, void *priv,
			    struct v4l2_input *inp)
{
	if (inp->index > 0)
		return -EINVAL;

	inp->type = V4L2_INPUT_TYPE_CAMERA;
	strscpy(inp->name, "Pattern generator", sizeof(inp->name));
	return 0;
}

static int vpatt_g_input(struct file *file, void *priv, unsigned int *i)
{
	*i = 0;
	return 0;
}

static int vpatt_s_input(struct file *file, void *priv, unsigned int i)
{
	return i ? -EINVAL : 0;
}

static const struct v4l2_ioctl_ops vpatt_ioctl_ops = {
	.vidioc_querycap		= vpatt_querycap,
	.vidioc_enum_fmt_vid_cap	= vpatt_enum_fmt,
	.vidioc_g_fmt_vid_cap		= vpatt_g_fmt,
	.vidioc_s_fmt_vid_cap		= vpatt_try_fmt,
	.vidioc_try_fmt_vid_cap		= vpatt_try_fmt,
	.vidioc_enum_framesizes		= vpatt_enum_framesizes,

	.vidioc_enum_input		= vpatt_enum_input,
	.vidioc_g_input			= vpatt_g_input,
	.vidioc_s_input			= vpatt_s_input,

	.vidioc_reqbufs			= vb2_ioctl_reqbufs,
	.vidioc_create_bufs		= vb2_ioctl_create_bufs,
	.vidioc_prepare_buf		= vb2_ioctl_prepare_buf,
	.vidioc_querybuf		= vb2_ioctl_querybuf,
	.vidioc_qbuf			= vb2_ioctl_qbuf,
	.vidioc_dqbuf			= vb2_ioctl_dqbuf,
	.vidioc_expbuf			= vb2_ioctl_expbuf,
	.vidioc_streamon		= vb2_ioctl_streamon,
	.vidioc_streamoff		= vb2_ioctl_streamoff,
};

static const struct v4l2_file_operations vpatt_fops = {
	.owner		= THIS_MODULE,
	.open		= v4l2_fh_open,
	.release	= vb2_fop_release,
	.poll		= vb2_fop_poll,
	.unlocked_ioctl	= video_ioctl2,
	.mmap		= vb2_fop_mmap,
	.read		= vb2_fop_read,
};

/* -------------------------------------------------------------------------
 * Probe / remove
 */

static void vpatt_set_default_format(struct vpatt_dev *vpatt,
				     u32 width, u32 height)
{
	struct v4l2_pix_format *f = &vpatt->format;

	f->width	= width;
	f->height	= height;
	f->pixelformat	= VPATT_PIXELFORMAT;
	f->field	= V4L2_FIELD_NONE;
	f->colorspace	= V4L2_COLORSPACE_SRGB;
	f->bytesperline	= width * VPATT_BPP;
	f->sizeimage	= f->bytesperline * height;
}

static int vpatt_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct vpatt_dev *vpatt;
	struct vb2_queue *q;
	u32 width = VPATT_DEF_WIDTH;
	u32 height = VPATT_DEF_HEIGHT;
	int ret;

	vpatt = devm_kzalloc(dev, sizeof(*vpatt), GFP_KERNEL);
	if (!vpatt)
		return -ENOMEM;

	vpatt->dev = dev;
	mutex_init(&vpatt->lock);
	spin_lock_init(&vpatt->qlock);
	INIT_LIST_HEAD(&vpatt->buf_list);
	platform_set_drvdata(pdev, vpatt);

	/* Geometry must match the m_axis_0 H_RES/V_RES generics. */
	of_property_read_u32(dev->of_node, "minized,width", &width);
	of_property_read_u32(dev->of_node, "minized,height", &height);
	vpatt_set_default_format(vpatt, width, height);

	/*
	 * Attach the private CMA pool from the device tree's memory-region,
	 * if there is one, before anything can allocate.  -ENODEV just means
	 * no region was described, in which case we fall back to the global
	 * CMA pool - which is prone to fragmentation for 1 MiB-aligned frames.
	 */
	ret = of_reserved_mem_device_init(dev);
	if (ret && ret != -ENODEV)
		return dev_err_probe(dev, ret,
				     "failed to attach reserved memory region\n");

	ret = dma_set_coherent_mask(dev, DMA_BIT_MASK(32));
	if (ret) {
		dev_err(dev, "failed to set DMA mask\n");
		goto err_rmem;
	}

	vpatt->dma = dma_request_chan(dev, "s2mm");
	if (IS_ERR(vpatt->dma)) {
		ret = PTR_ERR(vpatt->dma);
		dev_err_probe(dev, ret, "failed to request VDMA S2MM channel\n");
		goto err_rmem;
	}

	ret = v4l2_device_register(dev, &vpatt->v4l2_dev);
	if (ret) {
		dev_err(dev, "failed to register v4l2 device\n");
		goto err_dma;
	}

	q = &vpatt->queue;
	q->type			= V4L2_BUF_TYPE_VIDEO_CAPTURE;
	q->io_modes		= VB2_MMAP | VB2_DMABUF | VB2_READ;
	q->drv_priv		= vpatt;
	q->buf_struct_size	= sizeof(struct vpatt_buffer);
	q->ops			= &vpatt_qops;
	q->mem_ops		= &vb2_dma_contig_memops;
	q->timestamp_flags	= V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC;
	q->min_queued_buffers	= 2;
	q->lock			= &vpatt->lock;
	q->dev			= dev;

	ret = vb2_queue_init(q);
	if (ret) {
		dev_err(dev, "failed to initialise vb2 queue\n");
		goto err_v4l2;
	}

	vpatt->vdev.fops	= &vpatt_fops;
	vpatt->vdev.ioctl_ops	= &vpatt_ioctl_ops;
	vpatt->vdev.v4l2_dev	= &vpatt->v4l2_dev;
	vpatt->vdev.queue	= q;
	vpatt->vdev.lock	= &vpatt->lock;
	vpatt->vdev.release	= video_device_release_empty;
	vpatt->vdev.device_caps	= V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING |
				  V4L2_CAP_READWRITE;
	strscpy(vpatt->vdev.name, VPATT_DRV_NAME, sizeof(vpatt->vdev.name));
	video_set_drvdata(&vpatt->vdev, vpatt);

	ret = video_register_device(&vpatt->vdev, VFL_TYPE_VIDEO, -1);
	if (ret) {
		dev_err(dev, "failed to register video device\n");
		goto err_v4l2;
	}

	dev_info(dev, "/dev/video%d: %ux%u XBGR32 via %s\n",
		 vpatt->vdev.num, vpatt->format.width, vpatt->format.height,
		 dma_chan_name(vpatt->dma));

	return 0;

err_v4l2:
	v4l2_device_unregister(&vpatt->v4l2_dev);
err_dma:
	dma_release_channel(vpatt->dma);
err_rmem:
	of_reserved_mem_device_release(dev);
	return ret;
}

static void vpatt_remove(struct platform_device *pdev)
{
	struct vpatt_dev *vpatt = platform_get_drvdata(pdev);

	video_unregister_device(&vpatt->vdev);
	v4l2_device_unregister(&vpatt->v4l2_dev);
	dma_release_channel(vpatt->dma);
	of_reserved_mem_device_release(&pdev->dev);
}

static const struct of_device_id vpatt_of_match[] = {
	{ .compatible = "minized,vpatt-v4l2-1.0" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, vpatt_of_match);

static struct platform_driver vpatt_driver = {
	.probe	= vpatt_probe,
	.remove	= vpatt_remove,
	.driver	= {
		.name		= VPATT_DRV_NAME,
		.of_match_table	= vpatt_of_match,
	},
};

module_platform_driver(vpatt_driver);

MODULE_AUTHOR("Yosel Balibrea Lastre");
MODULE_DESCRIPTION("Minimal V4L2 capture for the MiniZed AXI-Stream pattern generator");
MODULE_LICENSE("GPL");
