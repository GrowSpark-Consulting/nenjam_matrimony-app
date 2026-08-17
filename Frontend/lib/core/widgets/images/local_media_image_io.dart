import 'dart:io';

import 'package:flutter/widgets.dart';

/// Android/iOS implementation — [path] is a real filesystem path, so the
/// bytes are read lazily off disk by [FileImage] rather than held in memory.
ImageProvider localMediaImageProvider(String path) => FileImage(File(path));
