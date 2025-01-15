extension ZipExtension<E1> on Iterable<E1> {
  Iterable<(E1, E2)> zip<E2>(Iterable<E2> other) sync* {
    var it1 = iterator;
    var it2 = other.iterator;
    while (it1.moveNext() && it2.moveNext()) {
      yield (it1.current, it2.current);
    }
  }
}
