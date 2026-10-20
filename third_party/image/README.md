# Local `image` compatibility patch

This directory contains `image` 4.11.0 from pub.dev, with its original licenses.
Only `lib/src/formats/png_decoder.dart` differs from the published package:
it uses `ZLibDecoder.decodeBytes` instead of `decodeLazy`. The latter requires
`archive` 4.4.0, while `pdf` 3.12.0 restricts `archive` to versions below 4.1.0.

Remove this override when the PDF dependency can use a compatible newer
`archive` and `image` combination. The replacement buffers decompressed PNG
data in memory, so large PNGs may use more memory during decoding.
