class Participant {
  const Participant({
    required this.userId,
    required this.name,
    required this.source,
    required this.target,
    required this.active,
  });
  final String userId, name, source, target;
  final bool active;
  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
    userId: json['user_id'] as String,
    name: json['display_name'] as String,
    source: json['source_language'] as String,
    target: json['target_language'] as String,
    active: json['left_at'] == null,
  );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.ownerId,
    required this.status,
    required this.expiresAt,
    required this.participants,
  });
  final String id, ownerId, status;
  final DateTime expiresAt;
  final List<Participant> participants;
  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    ownerId: json['created_by'] as String,
    status: json['status'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    participants: (json['participants'] as List)
        .map((p) => Participant.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
  );
}

class Allowance {
  const Allowance(this.plan, this.used, this.limit, this.estimatedCost);
  final String plan;
  final int used, limit;
  final num estimatedCost;
  factory Allowance.fromJson(Map<String, dynamic> json) => Allowance(
    json['plan'] as String,
    (json['used_seconds'] as num).toInt(),
    (json['limit_seconds'] as num).toInt(),
    json['estimated_cost_usd'] as num,
  );
}

const languageNames = {
  'en': 'English',
  'de': 'Deutsch',
  'ru': 'Русский',
  'tr': 'Türkçe',
  'uz': 'O‘zbekcha · experimental',
};
