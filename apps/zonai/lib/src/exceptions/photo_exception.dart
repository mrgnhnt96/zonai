sealed class PhotoException implements Exception {
  const PhotoException();
}

final class PhotosTableNotFoundException extends PhotoException {
  const PhotosTableNotFoundException();

  @override
  String toString() => 'Photos table not found';
}

final class InvalidPhotoIdException extends PhotoException {
  const InvalidPhotoIdException({required this.id});

  final String id;

  @override
  String toString() => 'Invalid photo id: $id';
}

final class InvalidPhotoPathException extends PhotoException {
  const InvalidPhotoPathException({required this.path});

  final String path;

  @override
  String toString() => 'Invalid photo path: $path';
}

final class PhotoNotFoundException extends PhotoException {
  const PhotoNotFoundException({this.id});

  final String? id;

  @override
  String toString() {
    if (id != null) return 'Photo not found: $id';
    return 'Photo not found';
  }
}

final class PhotoFileNotFoundException extends PhotoException {
  const PhotoFileNotFoundException({this.path});

  final String? path;

  @override
  String toString() {
    if (path != null) return 'Photo file not found: $path';
    return 'Photo file not found';
  }
}

final class PhotoFileAlreadyExistsException extends PhotoException {
  const PhotoFileAlreadyExistsException({required this.path});

  final String path;

  @override
  String toString() => 'Photo file already exists: $path';
}

final class PhotoContentTypeNotAllowedException extends PhotoException {
  const PhotoContentTypeNotAllowedException({required this.mimeType});

  final String mimeType;

  @override
  String toString() => 'Content type not allowed: $mimeType';
}

final class PhotoInsertFailedException extends PhotoException {
  const PhotoInsertFailedException();

  @override
  String toString() => 'Photo insert did not return a row';
}

final class PhotoImageTypeUndetectableException extends PhotoException {
  const PhotoImageTypeUndetectableException();

  @override
  String toString() => 'Could not detect image type from stream';
}
