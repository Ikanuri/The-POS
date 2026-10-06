import 'dart:typed_data';

/// BLAKE3 (mode hash, keluaran 32 byte) murni-Dart — dipakai HANYA untuk
/// menghitung hash berkas Cloudflare Pages Direct Upload
/// (`cloudflare_publish_service.dart`), yang mewajibkan BLAKE3. Tidak ada
/// dependency baru: implementasi mengikuti spesifikasi resmi dan diuji
/// terhadap vektor uji (lihat `test/blake3_test.dart`).
const _iv = <int>[
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, //
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];
const _perm = <int>[2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];
const _chunkStart = 1;
const _chunkEnd = 2;
const _parent = 4;
const _root = 8;
const _mask = 0xFFFFFFFF;

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _mask;

void _g(List<int> s, int a, int b, int c, int d, int mx, int my) {
  s[a] = (s[a] + s[b] + mx) & _mask;
  s[d] = _rotr(s[d] ^ s[a], 16);
  s[c] = (s[c] + s[d]) & _mask;
  s[b] = _rotr(s[b] ^ s[c], 12);
  s[a] = (s[a] + s[b] + my) & _mask;
  s[d] = _rotr(s[d] ^ s[a], 8);
  s[c] = (s[c] + s[d]) & _mask;
  s[b] = _rotr(s[b] ^ s[c], 7);
}

/// Kompresi satu blok. Mengembalikan 16 kata (8 pertama = chaining value).
List<int> _compress(
    List<int> cv, List<int> block, int counter, int blockLen, int flags) {
  final s = <int>[
    ...cv,
    _iv[0], _iv[1], _iv[2], _iv[3], //
    counter & _mask, (counter >> 32) & _mask, blockLen, flags,
  ];
  var m = List<int>.of(block);
  for (var r = 0; r < 7; r++) {
    _g(s, 0, 4, 8, 12, m[0], m[1]);
    _g(s, 1, 5, 9, 13, m[2], m[3]);
    _g(s, 2, 6, 10, 14, m[4], m[5]);
    _g(s, 3, 7, 11, 15, m[6], m[7]);
    _g(s, 0, 5, 10, 15, m[8], m[9]);
    _g(s, 1, 6, 11, 12, m[10], m[11]);
    _g(s, 2, 7, 8, 13, m[12], m[13]);
    _g(s, 3, 4, 9, 14, m[14], m[15]);
    if (r < 6) m = [for (final i in _perm) m[i]];
  }
  for (var i = 0; i < 8; i++) {
    s[i] ^= s[i + 8];
    s[i + 8] ^= cv[i];
  }
  return s;
}

List<int> _words(Uint8List data, int offset, int len) {
  final padded = Uint8List(64)..setRange(0, len, data, offset);
  final bd = ByteData.sublistView(padded);
  return [for (var i = 0; i < 16; i++) bd.getUint32(i * 4, Endian.little)];
}

/// CV satu chunk (<= 1024 byte). [rootOut] = chunk ini adalah akar pohon
/// (input <= 1 chunk) -> kembalikan keluaran akar penuh.
List<int> _chunk(Uint8List data, int start, int end, int counter,
    {required bool rootOut}) {
  var cv = List<int>.of(_iv);
  final len = end - start;
  final blocks = len == 0 ? 1 : (len + 63) ~/ 64;
  for (var b = 0; b < blocks; b++) {
    final off = start + b * 64;
    final bl = len == 0 ? 0 : (end - off < 64 ? end - off : 64);
    var flags = 0;
    if (b == 0) flags |= _chunkStart;
    if (b == blocks - 1) {
      flags |= _chunkEnd;
      if (rootOut) flags |= _root;
    }
    final out = _compress(cv, _words(data, off, bl), counter, bl, flags);
    if (b == blocks - 1 && rootOut) return out;
    cv = out.sublist(0, 8);
  }
  return cv;
}

List<int> _node(Uint8List data, int firstChunk, int count,
    {required bool rootOut}) {
  if (count == 1) {
    final s = firstChunk * 1024;
    final e = (s + 1024 < data.length) ? s + 1024 : data.length;
    return _chunk(data, s, e, firstChunk, rootOut: rootOut);
  }
  var left = 1;
  while (left * 2 < count) {
    left *= 2;
  }
  final l = _node(data, firstChunk, left, rootOut: false).sublist(0, 8);
  final r = _node(data, firstChunk + left, count - left, rootOut: false)
      .sublist(0, 8);
  final out =
      _compress(_iv, [...l, ...r], 0, 64, _parent | (rootOut ? _root : 0));
  return rootOut ? out : out.sublist(0, 8);
}

/// Hash BLAKE3 32 byte, heksadesimal huruf kecil (64 karakter).
String blake3Hex(List<int> input) {
  final data = input is Uint8List ? input : Uint8List.fromList(input);
  final chunks = data.isEmpty ? 1 : (data.length + 1023) ~/ 1024;
  final out = _node(data, 0, chunks, rootOut: true);
  final bd = ByteData(32);
  for (var i = 0; i < 8; i++) {
    bd.setUint32(i * 4, out[i], Endian.little);
  }
  return [
    for (final b in bd.buffer.asUint8List()) b.toRadixString(16).padLeft(2, '0')
  ].join();
}
