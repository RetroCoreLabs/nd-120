# Device test images (NOT in git)

The real disk images used by the device testbenches are large and stay
out of git (.gitignore covers *.img/*.IMG here). The testbenches print
a SKIP notice and still pass on their synthetic phases when an image is
missing; copy the files below to enable the real-image phases.

| File | Source | Used by |
|---|---|---|
| 210523I01-XX-01D.img | not published - the owner's archive of ND test-program diskettes | FLOPPY-DMA/sim (1261568 bytes, ND distribution diskette, 77x2x8x1024) |
| BIGDISK0-L2-100.IMG | not published - the owner's HDLC test setup (SMD disk 0) | SMD/sim (78643200 bytes = 75 MB SMD disk 0; windowed loading, the tb reads start/middle/end windows) |
