extension FutureExtension<T extends Object> on Future<T?> {
  Future<T> notNull() async => (await this)!;
}
