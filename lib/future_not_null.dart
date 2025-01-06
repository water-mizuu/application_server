extension FutureExtension<T extends Object> on Future<T?> {
  Future<T> notNull() async {
    T? value = await this;
    if (value == null) {
      throw StateError('Future is null');
    }
    return value;
  }
}