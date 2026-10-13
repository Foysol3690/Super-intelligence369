enum OrbState { idle, listening, thinking, speaking, error }

extension OrbStateLabel on OrbState {
  String get orbLabel => switch (this) {
        OrbState.idle => 'ONLINE',
        OrbState.listening => 'LISTEN',
        OrbState.thinking => 'THINK',
        OrbState.speaking => 'SPEAK',
        OrbState.error => 'ERROR',
      };

  String get semanticLabel => switch (this) {
        OrbState.idle => 'Maya is ready',
        OrbState.listening => 'Maya is listening',
        OrbState.thinking => 'Maya is thinking',
        OrbState.speaking => 'Maya is speaking',
        OrbState.error => 'Maya hit an error',
      };

  bool get isActive => this != OrbState.idle && this != OrbState.error;
}

class ChatTurn {
  const ChatTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}
