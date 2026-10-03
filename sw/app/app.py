#!/usr/bin/env python3
"""
cam_test - minimal Flask viewer for the MiniZed AXI4-Stream video pattern
generator (rtl/m_axis.v -> AXI VDMA -> /dev/video0).

Shows the core's output at its NATIVE 640x480.  minized_web_app ran every
frame through cv2.resize(frame, (350, 300)), which both downscaled it and
broke the 4:3 aspect ratio; nothing here resizes.

WHY NOT cv2.VideoCapture
------------------------
It works, but it caps out around 14 fps on this board, and measurement showed
why:

    grab() only  [pure V4L2 dequeue]     78.3 fps    12.8 ms   <- the core
    read()       [+ OpenCV XR24->BGR]    21.3 fps    47.0 ms
    read() + imencode                    14.1 fps    70.9 ms

The cost is not JPEG and not the hardware - it is that OpenCV converts pixels
*in place on the mmap'd DMA buffer*.  That mapping is uncached/write-combining,
so the strided reads a colour conversion does are ruinous, while a linear bulk
copy is fine:

    copy 1.2MB out of the DMA buffer      9.14 ms   (134 MB/s)
    cvtColor read from the DMA buffer    43.13 ms   ( 28 MB/s)
    cvtColor read from a cached copy      8.36 ms   (147 MB/s)

So the fastest loop deliberately adds a copy that looks redundant, then lets
OpenCV do the BGRA->JPEG conversion itself:

    cvtColor(DMA) + encode   [old]       14.6 fps   68.4 ms
    copy -> cvtColor -> encode           25.3 fps   39.5 ms
    copy -> encode 4ch directly          31.2 fps   32.1 ms   <- this one

JPEG_QUALITY barely matters (31.2 fps at q80 vs 31.3 at q30) - the pattern is
mostly flat colour, so the cost is the colour transform and DCT, not entropy
coding.  Lower it only if you want smaller frames on the wire.
"""

import ctypes
import fcntl
import mmap
import os
import threading
import time

import cv2
import numpy as np
from flask import Flask, Response, jsonify, render_template

DEVICE = "/dev/video0"
WIDTH, HEIGHT = 640, 480
NBUFFERS = 4
JPEG_QUALITY = 80

app = Flask(__name__)

# --- just enough of videodev2.h --------------------------------------------

def _IOC(d, t, nr, size):
    return (d << 30) | (size << 16) | (ord(t) << 8) | nr


class _timeval(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]


class _timecode(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("frames", ctypes.c_uint8), ("seconds", ctypes.c_uint8),
                ("minutes", ctypes.c_uint8), ("hours", ctypes.c_uint8),
                ("userbits", ctypes.c_uint8 * 4)]


class _bufm(ctypes.Union):
    _fields_ = [("offset", ctypes.c_uint32), ("userptr", ctypes.c_ulong),
                ("planes", ctypes.c_void_p), ("fd", ctypes.c_int32)]


class v4l2_buffer(ctypes.Structure):
    _fields_ = [("index", ctypes.c_uint32), ("type", ctypes.c_uint32),
                ("bytesused", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("field", ctypes.c_uint32), ("timestamp", _timeval),
                ("timecode", _timecode), ("sequence", ctypes.c_uint32),
                ("memory", ctypes.c_uint32), ("m", _bufm),
                ("length", ctypes.c_uint32), ("reserved2", ctypes.c_uint32),
                ("request_fd", ctypes.c_int32)]


class v4l2_requestbuffers(ctypes.Structure):
    _fields_ = [("count", ctypes.c_uint32), ("type", ctypes.c_uint32),
                ("memory", ctypes.c_uint32), ("capabilities", ctypes.c_uint32),
                ("flags", ctypes.c_uint8), ("reserved", ctypes.c_uint8 * 3)]


BUF_TYPE_CAPTURE = 1
MEMORY_MMAP = 1
VIDIOC_REQBUFS = _IOC(3, 'V', 8, ctypes.sizeof(v4l2_requestbuffers))
VIDIOC_QUERYBUF = _IOC(3, 'V', 9, ctypes.sizeof(v4l2_buffer))
VIDIOC_QBUF = _IOC(3, 'V', 15, ctypes.sizeof(v4l2_buffer))
VIDIOC_DQBUF = _IOC(3, 'V', 17, ctypes.sizeof(v4l2_buffer))
VIDIOC_STREAMON = _IOC(1, 'V', 18, 4)
VIDIOC_STREAMOFF = _IOC(1, 'V', 19, 4)


class Camera:
    """One grabber thread; every client is served the most recent frame.

    The core free-runs with no backpressure, so queueing per client would only
    add latency - a viewer always wants the newest frame.  JPEG encoding
    happens once here regardless of how many browsers are connected.
    """

    def __init__(self):
        try:
            self.fd = os.open(DEVICE, os.O_RDWR)
        except OSError as e:
            raise RuntimeError(
                "cannot open %s (%s) - is vpatt-v4l2 loaded, and are you in "
                "the 'video' group?" % (DEVICE, e.strerror))

        req = v4l2_requestbuffers(count=NBUFFERS, type=BUF_TYPE_CAPTURE,
                                  memory=MEMORY_MMAP)
        fcntl.ioctl(self.fd, VIDIOC_REQBUFS, req)

        self.maps, self.views = [], []
        for i in range(req.count):
            b = v4l2_buffer(index=i, type=BUF_TYPE_CAPTURE, memory=MEMORY_MMAP)
            fcntl.ioctl(self.fd, VIDIOC_QUERYBUF, b)
            m = mmap.mmap(self.fd, b.length, mmap.MAP_SHARED,
                          mmap.PROT_READ | mmap.PROT_WRITE, offset=b.m.offset)
            self.maps.append(m)
            self.views.append(
                np.frombuffer(m, dtype=np.uint8).reshape(HEIGHT, WIDTH, 4))
            fcntl.ioctl(self.fd, VIDIOC_QBUF, b)

        fcntl.ioctl(self.fd, VIDIOC_STREAMON, ctypes.c_int(BUF_TYPE_CAPTURE))

        self.jpeg = None
        self.seq = 0
        self.fps = 0.0
        self.lock = threading.Lock()
        self.cond = threading.Condition(self.lock)
        threading.Thread(target=self._grab, daemon=True).start()

    def _grab(self):
        params = [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY]
        t0, n = time.monotonic(), 0
        while True:
            b = v4l2_buffer(type=BUF_TYPE_CAPTURE, memory=MEMORY_MMAP)
            fcntl.ioctl(self.fd, VIDIOC_DQBUF, b)

            # The copy is NOT redundant - see the module docstring.  Bulk-copy
            # out of the write-combining DMA mapping, then let OpenCV do
            # BGRA->JPEG against ordinary cached memory.
            frame = np.array(self.views[b.index])

            fcntl.ioctl(self.fd, VIDIOC_QBUF, b)   # requeue promptly

            ok, buf = cv2.imencode(".jpg", frame, params)
            if not ok:
                continue

            with self.cond:
                self.jpeg = buf.tobytes()
                self.seq += 1
                self.cond.notify_all()

            n += 1
            dt = time.monotonic() - t0
            if dt >= 1.0:
                self.fps = n / dt
                t0, n = time.monotonic(), 0

    def frames(self):
        """Yield each new frame once, blocking until one arrives."""
        last = 0
        while True:
            with self.cond:
                self.cond.wait_for(lambda: self.seq != last, timeout=5.0)
                if self.seq == last:
                    continue
                last, jpeg = self.seq, self.jpeg
            yield jpeg


_camera = None
_camera_lock = threading.Lock()


def camera():
    global _camera
    with _camera_lock:
        if _camera is None:
            _camera = Camera()
    return _camera


@app.route("/")
def index():
    return render_template("index.html", width=WIDTH, height=HEIGHT)


@app.route("/stream")
def stream():
    def gen():
        for jpeg in camera().frames():
            yield (b"--frame\r\n"
                   b"Content-Type: image/jpeg\r\n"
                   b"Content-Length: " + str(len(jpeg)).encode() + b"\r\n\r\n"
                   + jpeg + b"\r\n")

    return Response(gen(),
                    mimetype="multipart/x-mixed-replace; boundary=frame")


@app.route("/stats")
def stats():
    cam = camera()
    return jsonify(fps=round(cam.fps, 1), frames=cam.seq,
                   size=[WIDTH, HEIGHT], quality=JPEG_QUALITY)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, threaded=True)
