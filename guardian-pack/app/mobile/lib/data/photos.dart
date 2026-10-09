import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Profile photos are stored *in Firestore* as small base64 JPEG data URIs
/// (≈15–30 KB at 256 px), not in Cloud Storage: new Firebase projects need the
/// paid plan for Storage, and avatars are the only images this app has.
/// Firestore documents allow 1 MB, so this stays well inside.

const _side = 256;
const _quality = 82;

/// Lets the parent pick a photo (gallery or camera), squares and shrinks it.
/// Returns a `data:image/jpeg;base64,...` string, or null if cancelled.
Future<String?> pickAvatarDataUri({bool camera = false}) async {
  final x = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1024,          // picker-side downscale keeps decode cheap
    maxHeight: 1024,
    imageQuality: 90,
  );
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  return encodeAvatar(bytes);
}

/// Centre-crop to a square, resize to 256 px, encode JPEG, wrap as a data URI.
String? encodeAvatar(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) return null;
  im = img.bakeOrientation(im);                 // honour EXIF rotation from cameras
  final s = im.width < im.height ? im.width : im.height;
  im = img.copyCrop(im, x: (im.width - s) ~/ 2, y: (im.height - s) ~/ 2, width: s, height: s);
  im = img.copyResize(im, width: _side, height: _side, interpolation: img.Interpolation.average);
  final jpg = img.encodeJpg(im, quality: _quality);
  return 'data:image/jpeg;base64,${base64Encode(jpg)}';
}

/// Decodes a data URI produced above (or any base64 image) for an Image widget.
Uint8List? avatarBytes(String? dataUri) {
  if (dataUri == null || dataUri.isEmpty) return null;
  final comma = dataUri.indexOf(',');
  try {
    return base64Decode(comma >= 0 ? dataUri.substring(comma + 1) : dataUri);
  } catch (_) {
    return null;
  }
}
