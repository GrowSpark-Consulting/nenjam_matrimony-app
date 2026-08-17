import 'package:flutter/widgets.dart';

/// Web implementation — a locally-picked file has no filesystem path in the
/// browser. `XFile.path` is instead a `blob:` object URL that the browser
/// resolves from its own in-memory store, which [NetworkImage] can fetch
/// directly. This file deliberately contains no `dart:io` import, so nothing
/// in the web bundle can reach `File`.
ImageProvider localMediaImageProvider(String blobUrl) => NetworkImage(blobUrl);
