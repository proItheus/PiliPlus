class LocalSubscription {
  const LocalSubscription({required this.mid, this.name, this.face, this.sign});

  final int mid;
  final String? name;
  final String? face;
  final String? sign;

  factory LocalSubscription.fromJson(Map<String, dynamic> json) {
    final rawMid = json['mid'];
    final mid = rawMid is num
        ? rawMid.toInt()
        : int.tryParse(rawMid?.toString() ?? '');
    if (mid == null || mid <= 0) {
      throw const FormatException('无效的用户 ID');
    }
    return LocalSubscription(
      mid: mid,
      name: json['name'] as String?,
      face: json['face'] as String?,
      sign: json['sign'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'mid': mid,
    if (name != null) 'name': name,
    if (face != null) 'face': face,
    if (sign != null) 'sign': sign,
  };
}
