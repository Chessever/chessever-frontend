class Pv {
  final int id;
  final int evalId;
  final int idx;
  final int? cp;
  final int? mate;
  final String line;

  Pv({required this.id, required this.evalId, required this.idx, this.cp, this.mate, required this.line});

  factory Pv.fromJson(Map<String, dynamic> json) => Pv(
    id: json['id'],
    evalId: json['eval_id'],
    idx: json['idx'],
    cp: json['cp'],
    mate: json['mate'],
    line: json['line'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'eval_id': evalId,
    'idx': idx,
    'cp': cp,
    'mate': mate,
    'line': line,
  };
}