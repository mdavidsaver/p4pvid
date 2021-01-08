
import numpy

# not entirely sure where this comes from, but the result looks right.
# YUV = RGB._rgb2yuv + _rgboffset.repeat((W, H))
_rgb2yuv=numpy.asarray([[0.29900, -0.16874,  0.50000],
                        [0.58700, -0.33126, -0.41869],
                        [0.11400,  0.50000, -0.08131]])
_rgboffset = numpy.asarray([[[128.0, 128.0, 128.0]]])

_yuv2rgb=numpy.linalg.inv(_rgb2yuv)
_yuvoffset = numpy.asarray([[[-179.45477266423404, 135.45870971679688, -226.8183044444304]]])

def yuv422_rgb24(yuv):
    # just the Y component gives a gray scale image
    #return yuv[:,:,0]

    # distinguish U from V with a red.
    #return yuv[:, 1::2, 1] # red -> white, V
    #return yuv[:, 0::2, 1] # red -> black, U

    y1 = yuv[:, 0::2, 0:1]
    u  = yuv[:, 0::2, 1:2]
    y2 = yuv[:, 1::2, 0:1]
    v  = yuv[:, 1::2, 1:2]

    even = numpy.concatenate((y1, u, v), axis=2) # [H, W, 3]
    odd  = numpy.concatenate((y2, u, v), axis=2)

    even = numpy.dot(even, _yuv2rgb)
    odd  = numpy.dot(odd, _yuv2rgb)

    offset = _yuvoffset.repeat(yuv.shape[0], 0).repeat(yuv.shape[1]/2, 1)
    even += offset
    odd += offset

    out = numpy.ndarray((yuv.shape[0], yuv.shape[1], 3), dtype=yuv.dtype)
    out[:, 0::2, :] = even.clip(0, 255)
    out[:, 1::2, :] = odd.clip(0, 255)
    return out

_mangle = {
    b'YUYV':yuv422_rgb24,
    # assume multi-byte gray is LSB
    b'Y12 ':lambda I:numpy.frombuffer(I, '<u2').reshape(I.shape[:2]),
    b'Y16 ':lambda I:numpy.frombuffer(I, '<u2').reshape(I.shape[:2]),
    # formats which need no special handling
    b'GRAY':numpy.asarray,
    b'RGB3':numpy.asarray,
    # partially supported YUV modes.  Provide only Y's as a gray scale
    b'Y444':lambda I:I[:,:,1],
    b'YVYU':lambda I:I[:,:,0],
    b'UYVY':lambda I:I[:,:,1],
}
