"""Stream a video4linux2 device via PVA

python capture.py /dev/video0 pv:name
"""
from __future__ import print_function

import numpy
import sys

from p4p.nt.ndarray import NTNDArray, ntndarray
from p4p.server.thread import SharedPV
from p4p.server import Server, StaticProvider

from . import v4l, color

pv = SharedPV(nt=NTNDArray(),
              initial=numpy.zeros((0,0), dtype='u1'))
provider = StaticProvider('capture')
provider.add(sys.argv[2], pv)

# open the capture device, and run the Server
with open(sys.argv[1], 'r+b', 0) as F, Server(providers=[provider]):
    caps = v4l.query_capabilities(F.fileno())

    print('capabilities', caps)

    if 'VIDEO_CAPTURE' not in caps['capabilities']:
        print("Not a capture device")
        sys.exit(1)

    idx = -1
    for fmt in v4l.list_formats(F.fileno()):
        print('Supported:', fmt)
        if fmt['pixelformat'] in color._mangle:
            idx = fmt['index']
            # don't break, use last.
            # this assumes gray scale is listed first

    if idx==-1:
        print("No supported pixel format")
        sys.exit(1)

    v4l.set_format(F.fileno(), idx)

    fmt = v4l.get_format(F.fileno())
    print('Selected Format:', fmt)
    mangle = color._mangle[fmt['pixelformat']]

    nbufs = v4l.alloc_buffers(F.fileno(), 8)
    print("Allocated frames:", nbufs)
    assert nbufs>=2, nbufs

    # prepare (mmap) frame buffers
    bufs = [v4l.Buffer(F.fileno(), i) for i in range(nbufs)]

    # queue all
    [v4l.buffer_push(F.fileno(), B.index) for B in bufs]

    # begin streaming
    v4l.capture(F.fileno(), True)

    try:
        while True:
            idx = v4l.buffer_pop(F.fileno())

            B=mangle(numpy.asarray(bufs[idx])).copy()
            # make a paranoia copy to ensure we can safely re-queue

            # (Optional) inject custom attributes
            B = B.view(ntndarray) # buffer not copied
            B.attrib = {'blah':3}

            pv.post(B)

            v4l.buffer_push(F.fileno(), idx)

    finally:
        # end streaming.  implicitly dequeues all buffers
        v4l.capture(F.fileno(), False)
