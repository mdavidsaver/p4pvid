#cython: language_level=2

from libc.stdint cimport uint32_t
from libc.errno cimport errno, EINVAL
from posix.ioctl cimport ioctl
from posix.time cimport timeval
from posix.mman cimport mmap, munmap, PROT_READ, PROT_WRITE, MAP_SHARED

cdef extern from "<endian.h>":
    uint32_t le32toh(uint32_t)

cdef extern from "<linux/videodev2.h>":
    enum: VIDIOC_QUERYCAP
    struct v4l2_capability:
        char* driver
        char* card
        char* bus_info
        int version
        int capabilities
        int device_caps
    enum: V4L2_CAP_VIDEO_CAPTURE
    enum: V4L2_CAP_READWRITE
    enum: V4L2_CAP_ASYNCIO
    enum: V4L2_CAP_STREAMING
    enum: V4L2_CAP_DEVICE_CAPS
    enum: V4L2_CAP_EXT_PIX_FORMAT

    enum: VIDIOC_ENUM_FMT
    struct v4l2_fmtdesc:
        uint32_t index
        uint32_t type # V4L2_BUF_TYPE_*
        uint32_t flags # V4L2_FMT_FLAG_*
        char* description
        uint32_t pixelformat
    enum: V4L2_BUF_TYPE_VIDEO_CAPTURE
    enum: V4L2_FMT_FLAG_COMPRESSED
    enum: V4L2_FMT_FLAG_EMULATED

    struct v4l2_pix_format:
        uint32_t width
        uint32_t height
        uint32_t pixelformat
        int field # V4L2_FIELD_*
        uint32_t bytesperline
        uint32_t sizeimage
        int colorspace # V4L2_COLORSPACE_*
        uint32_t priv
        # remaining valid priv& V4L2_PIX_FMT_PRIV_MAGIC and check V4L2_CAP_EXT_PIX_FORMAT
        uint32_t flags
        int ycbcr_enc
        int quantization
        int xfer_func
    enum: V4L2_FIELD_NONE
    enum: V4L2_COLORSPACE_DEFAULT
    enum: V4L2_COLORSPACE_RAW
    enum: V4L2_COLORSPACE_JPEG
    enum: V4L2_PIX_FMT_GREY
    enum: V4L2_PIX_FMT_YUYV
    enum: V4L2_PIX_FMT_PRIV_MAGIC

    enum: VIDIOC_G_FMT
    enum: VIDIOC_S_FMT
    enum: VIDIOC_TRY_FMT
    union v4l2_format_:
        v4l2_pix_format pix
        #v4l2_pix_format_mplane 	pix_mp
        #v4l2_window win
        #v4l2_vbi_format vbi
        #v4l2_sliced_vbi_format sliced
        #v4l2_sdr_format sdr
    struct v4l2_format:
        int type  # V4L2_BUF_TYPE_*
        v4l2_format_ fmt

    enum: VIDIOC_REQBUFS
    struct v4l2_requestbuffers:
        uint32_t count
        uint32_t type  # V4L2_BUF_TYPE_*
        uint32_t memory # V4L2_MEMORY_*
    enum: V4L2_MEMORY_MMAP

    union v4l2_buffer_m_:
        uint32_t offset
        # others omitted

    enum: VIDIOC_QUERYBUF
    enum: VIDIOC_QBUF
    enum: VIDIOC_DQBUF
    struct v4l2_buffer:
        uint32_t index
        uint32_t type
        uint32_t bytesused
        uint32_t flags
        uint32_t field
        timeval timestamp
        #v4l2_timecode    timecode
        uint32_t sequence
        uint32_t memory
        v4l2_buffer_m_ m
        uint32_t length

    enum: VIDIOC_STREAMON
    enum: VIDIOC_STREAMOFF

cap_map = (
    ('VIDEO_CAPTURE', V4L2_CAP_VIDEO_CAPTURE),
    ('READWRITE', V4L2_CAP_READWRITE),
    ('ASYNCIO', V4L2_CAP_ASYNCIO),
    ('STREAMING', V4L2_CAP_STREAMING),
    ('EXT_PIX_FORMAT', V4L2_CAP_EXT_PIX_FORMAT),
    # many others omitted
)

cdef fourcc(uint32_t code):
    cdef char cc[4]
    code = le32toh(code)
    cc[0] = code
    cc[1] = code>>8
    cc[2] = code>>16
    cc[3] = code>>24
    return cc

cdef map_caps(uint32_t cap):
    ret = set()

    for name, mask in cap_map:
        if cap&mask:
            ret.add(name)
    return ret

def query_capabilities(int fd):
    cdef int err
    cdef v4l2_capability cap

    err = ioctl(fd, VIDIOC_QUERYCAP, &cap)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_QUERYCAP)')

    ret = {
        'driver': <const char*>cap.driver,
        'card': <const char*>cap.card,
        'bus_info': <const char*>cap.bus_info,
        'version': cap.version,
        'capabilities':map_caps(cap.capabilities),
        'device_caps':set()
    }
    if cap.capabilities & V4L2_CAP_DEVICE_CAPS:
        ret['device_caps'] = map_caps(cap.device_caps)
    return ret

def list_formats(int fd):
    cdef int err
    cdef v4l2_fmtdesc desc

    desc.index = 0
    desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
    ret = []
    while True:
        err = ioctl(fd, VIDIOC_ENUM_FMT, &desc)
        if err==-1:
            if errno==EINVAL:
                break # done
            else:
                raise OSError(errno, 'ioctl(VIDIOC_ENUM_FMT)')

        flags = set()
        if desc.flags & V4L2_FMT_FLAG_COMPRESSED:
            flags.add('COMPRESSED')
        if desc.flags & V4L2_FMT_FLAG_EMULATED:
            flags.add('EMULATED')

        ret.append({
            'index': desc.index, # implied by list index, but include anyway
            'description': <const char*>desc.description,
            'pixelformat': fourcc(desc.pixelformat),
            'flags': flags,
        })
        desc.index+=1

    return ret

def get_format(int fd):
    cdef int err
    cdef v4l2_format fmt

    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE

    err = ioctl(fd, VIDIOC_G_FMT, &fmt)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_G_FMT)')

    return {
        'width': fmt.fmt.pix.width,
        'height': fmt.fmt.pix.height,
        'pixelformat': fourcc(fmt.fmt.pix.pixelformat),
        'bytesperline': fmt.fmt.pix.bytesperline,
        'field': fmt.fmt.pix.field,
        'sizeimage': fmt.fmt.pix.sizeimage,
        'colorspace': fmt.fmt.pix.colorspace,
    }

def set_format(int fd, int idx):
    cdef int err
    cdef v4l2_fmtdesc desc
    cdef v4l2_format fmt

    desc.index = idx
    desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE

    err = ioctl(fd, VIDIOC_ENUM_FMT, &desc)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_ENUM_FMT, %d)'%idx)

    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE

    fmt.fmt.pix.pixelformat = desc.pixelformat
    # let driver select defaults
    fmt.fmt.pix.width = 0xffff
    fmt.fmt.pix.height = 0xffff
    fmt.fmt.pix.bytesperline = 0
    fmt.fmt.pix.sizeimage = 0
    # we only understand non-interlaced (progressive)
    fmt.fmt.pix.field = V4L2_FIELD_NONE
    fmt.fmt.pix.colorspace = V4L2_COLORSPACE_DEFAULT

    err = ioctl(fd, VIDIOC_S_FMT, &fmt)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_S_FMT)')

def alloc_buffers(int fd, int count):
    cdef int err
    cdef v4l2_requestbuffers req

    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
    req.memory = V4L2_MEMORY_MMAP
    req.count = count

    err = ioctl(fd, VIDIOC_REQBUFS, &req)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_REQBUFS, %d)'%count)

    return req.count # actual number allocated

def capture(int fd, on):
    cdef int err
    cdef int arg = V4L2_BUF_TYPE_VIDEO_CAPTURE
    cdef unsigned long op = VIDIOC_STREAMOFF

    if on:
        op = VIDIOC_STREAMON

    err = ioctl(fd, op, &arg)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_STREAMx, %s)'%on)

cdef class Buffer:
    cdef v4l2_buffer buf
    cdef void* base
    cdef Py_ssize_t shape[3]
    cdef Py_ssize_t strides[3]
    cdef v4l2_format fmt

    def __cinit__(self, int fd, int index):
        cdef int err

        self.fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE

        err = ioctl(fd, VIDIOC_G_FMT, &self.fmt)
        if err==-1:
            raise OSError(errno, 'ioctl(VIDIOC_G_FMT)')

        self.buf.index = index
        self.buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
        self.buf.memory = V4L2_MEMORY_MMAP

        err = ioctl(fd, VIDIOC_QUERYBUF, &self.buf)
        if err==-1:
            raise OSError(errno, 'ioctl(VIDIOC_QUERYBUF, %d)'%index)

        self.base = mmap(NULL, self.buf.length,
                         PROT_READ|PROT_WRITE, MAP_SHARED,
                         fd, self.buf.m.offset)
        if self.base==<void*>-1:
            raise OSError(errno, 'mmap(%d)'%index)

    def __dealloc__(self):
        munmap(self.base, self.buf.length)

    @property
    def index(self):
        return self.buf.index

    def __getbuffer__(self, Py_buffer *view, int flags):
        # Present buffer as either (height, width) or heigh, width, depth)
        # when depth!=1.  Always in bytes.
        cdef unsigned bpp = self.fmt.fmt.pix.bytesperline/self.fmt.fmt.pix.width

        view.buf = self.base
        view.obj = self
        view.internal = NULL
        view.readonly = 0
        view.suboffsets = NULL

        self.shape[2] = bpp
        self.shape[1] = self.fmt.fmt.pix.width
        self.shape[0] = self.fmt.fmt.pix.height
        self.strides[2] = 1
        self.strides[1] = self.shape[2]
        self.strides[0] = self.shape[2]*self.shape[1]
        view.shape = self.shape
        view.strides = self.strides

        # defaults
        view.format = 'B'
        view.itemsize = 1
        if bpp==1:
            view.ndim = 2
        else:
            view.ndim = 3

def buffer_push(int fd, int index):
    cdef int err
    cdef v4l2_buffer buf

    buf.index = index
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
    buf.memory = V4L2_MEMORY_MMAP

    err = ioctl(fd, VIDIOC_QBUF, &buf)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_QBUF, %d)'%index)

def buffer_pop(int fd):
    cdef int err
    cdef v4l2_buffer buf

    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
    buf.memory = V4L2_MEMORY_MMAP

    err = ioctl(fd, VIDIOC_DQBUF, &buf)
    if err==-1:
        raise OSError(errno, 'ioctl(VIDIOC_DQBUF)')

    return buf.index
