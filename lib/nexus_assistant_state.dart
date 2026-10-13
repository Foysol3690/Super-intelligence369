/// The five assistant phases the home screen can visualise.
enum NexusAssistantState {
  idle,
  listening,
  processing,
  thinking,
  speaking;

  String get headline => switch (this) {
        NexusAssistantState.idle => 'MAYA READY',
        NexusAssistantState.listening => 'LISTENING',
        NexusAssistantState.processing => 'PROCESSING',
        NexusAssistantState.thinking => 'THINKING',
        NexusAssistantState.speaking => 'SPEAKING',
      };

  String get hint => switch (this) {
        NexusAssistantState.idle => 'TAP THE ORB TO SPEAK',
        NexusAssistantState.listening => 'TAP THE ORB TO SEND',
        NexusAssistantState.processing => 'ROUTING SIGNAL',
        NexusAssistantState.thinking => 'SYNTHESIZING RESPONSE',
        NexusAssistantState.speaking => 'TAP TO INTERRUPT',
      };

  String get orbStatus => switch (this) {
        NexusAssistantState.idle => 'READY',
        NexusAssistantState.listening => 'LISTENING',
        NexusAssistantState.processing => 'ROUTING',
        NexusAssistantState.thinking => 'THINKING',
        NexusAssistantState.speaking => 'SPEAKING',
      };
}
